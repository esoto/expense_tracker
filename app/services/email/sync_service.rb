# frozen_string_literal: true

module Email
    # SyncService consolidates synchronization operations including
    # session management, conflict detection, progress tracking, and metrics.
    # This is a simplified version that maintains backward compatibility
    # while adding essential consolidated features.
    class SyncService
      class SyncError < StandardError; end

      attr_reader :sync_session, :metrics, :errors

      def initialize(options = {})
        @options = options
        @metrics = {}
        @errors = []
      end

      # Main entry point - maintains backward compatibility
      def sync_emails(email_account_id: nil)
        if email_account_id.present?
          sync_specific_account(email_account_id)
        else
          sync_all_accounts
        end
      end

      # Create sync session for tracking
      def create_session(email_account = nil)
        @sync_session = SyncSession.create!(
          status: "pending",
          total_accounts: email_account ? 1 : EmailAccount.active.count,
          started_at: Time.current
        )

        if email_account
          @sync_session.sync_session_accounts.create!(
            email_account: email_account,
            status: "pending"
          )
        end

        @sync_session
      end

      # Update sync progress
      def update_progress(status: nil, message: nil, processed: 0, total: 0)
        return unless @sync_session

        @sync_session.update!(
          status: status || @sync_session.status,
          processed_emails_count: processed,
          total_emails_count: total,
          last_activity_at: Time.current
        )

        broadcast_progress(message) if @options[:broadcast_progress]
      end

      # Retry failed sync
      def retry_failed_session(session_id)
        session = SyncSession.find(session_id)

        return { success: false, error: "Session not found" } unless session
        return { success: false, error: "Session not failed" } unless session.failed?

        session.update!(
          status: "retrying",
          retry_count: session.retry_count + 1
        )

        # Re-run sync for failed accounts
        session.sync_session_accounts.failed.each do |account_session|
          ProcessEmailsJob.perform_later(account_session.email_account_id)
        end

        { success: true, message: "Retry initiated for session #{session_id}" }
      end

      # Get sync metrics
      def get_metrics(time_window: 1.hour)
        {
          total_syncs: SyncSession.where(created_at: time_window.ago..Time.current).count,
          successful_syncs: SyncSession.completed.where(created_at: time_window.ago..Time.current).count,
          failed_syncs: SyncSession.failed.where(created_at: time_window.ago..Time.current).count,
          average_duration: calculate_average_duration(time_window),
          emails_processed: calculate_emails_processed(time_window),
          conflicts_detected: calculate_conflicts(time_window)
        }
      end

      # Detect conflicts (simplified)
      def detect_conflicts
        conflicts = []

        # Find potential duplicate expenses
        recent_expenses = Expense.where(created_at: 1.hour.ago..Time.current)

        recent_expenses.group_by { |e| [ e.date, e.amount.round(2) ] }.each do |_, expenses|
          next if expenses.count < 2

          expenses.combination(2).each do |exp1, exp2|
            if similar_descriptions?(exp1.description, exp2.description)
              conflicts << {
                type: "duplicate",
                expenses: [ exp1.id, exp2.id ],
                confidence: 0.8
              }
            end
          end
        end

        conflicts
      end

      # Resolve conflicts automatically
      def resolve_conflicts(conflicts, strategy: :keep_newest)
        resolved = 0

        conflicts.each do |conflict|
          case conflict[:type]
          when "duplicate"
            if strategy == :keep_newest
              expenses = Expense.find(conflict[:expenses])
              keeper = expenses.max_by(&:created_at)

              expenses.each do |expense|
                next if expense == keeper
                expense.update!(status: "duplicate", duplicate_of_id: keeper.id)
              end

              resolved += 1
            end
          end
        end

        { resolved: resolved, total: conflicts.count }
      end

      private

      def sync_specific_account(email_account_id)
        email_account = EmailAccount.find_by(id: email_account_id)

        if email_account.nil?
          raise SyncError, "Cuenta de correo no encontrada."
        end

        unless email_account.active?
          raise SyncError, "La cuenta de correo está inactiva."
        end

        # Create session if tracking is enabled
        create_session(email_account) if @options[:track_session]

        ProcessEmailsJob.perform_later(email_account.id)

        {
          success: true,
          message: "Sincronización iniciada para #{email_account.email}. Los nuevos gastos aparecerán en unos momentos.",
          email_account: email_account,
          session_id: @sync_session&.id
        }
      end

      def sync_all_accounts
        active_accounts = EmailAccount.active

        if active_accounts.count == 0
          raise SyncError, "No hay cuentas de correo activas configuradas."
        end

        # Create session if tracking is enabled
        create_session if @options[:track_session]

        ProcessEmailsJob.perform_later

        # Detect and resolve conflicts if enabled
        if @options[:detect_conflicts]
          conflicts = detect_conflicts
          resolve_conflicts(conflicts) if conflicts.any? && @options[:auto_resolve]
        end

        {
          success: true,
          message: "Sincronización iniciada para #{active_accounts.count} cuenta#{'s' if active_accounts.count != 1} de correo. Los nuevos gastos aparecerán en unos momentos.",
          account_count: active_accounts.count,
          session_id: @sync_session&.id
        }
      end

      def broadcast_progress(message)
        return unless @sync_session

        ActionCable.server.broadcast(
          "sync_progress_#{@sync_session.id}",
          {
            session_id: @sync_session.id,
            status: @sync_session.status,
            message: message,
            progress: calculate_progress_percentage
          }
        )
      end

      def calculate_progress_percentage
        return 0 unless @sync_session&.total_emails_count&.positive?

        ((@sync_session.processed_emails_count.to_f / @sync_session.total_emails_count) * 100).round
      end

      def calculate_average_duration(time_window)
        sessions = SyncSession.completed.where(created_at: time_window.ago..Time.current)

        return 0 if sessions.empty?

        durations = sessions.map { |s| s.completed_at - s.started_at if s.completed_at && s.started_at }.compact

        return 0 if durations.empty?

        durations.sum / durations.count
      end

      def calculate_emails_processed(time_window)
        SyncSession.where(created_at: time_window.ago..Time.current).sum(:processed_emails_count)
      end

      def calculate_conflicts(time_window)
        SyncSession.where(created_at: time_window.ago..Time.current).sum(:conflicts_detected)
      end

      def similar_descriptions?(desc1, desc2)
        return false if desc1.nil? || desc2.nil?

        # Simple similarity check
        words1 = desc1.downcase.split(/\W+/)
        words2 = desc2.downcase.split(/\W+/)

        common = words1 & words2
        return false if common.empty?

        similarity = common.length.to_f / [ words1.length, words2.length ].min
        similarity > 0.7
      end
    end
end

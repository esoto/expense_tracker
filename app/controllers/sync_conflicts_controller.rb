class SyncConflictsController < ApplicationController
  before_action :set_sync_conflict, only: [ :show, :resolve, :undo, :preview_merge ]
  before_action :set_sync_session, only: [ :index, :bulk_resolve ]

  def index
    @conflicts = if @sync_session
      @sync_session.sync_conflicts.includes(:existing_expense, :new_expense)
    else
      SyncConflict.includes(:existing_expense, :new_expense)
    end

    # Apply filters
    @conflicts = @conflicts.where(status: params[:status]) if params[:status].present?
    @conflicts = @conflicts.where(conflict_type: params[:type]) if params[:type].present?

    # Sort and paginate
    page = [ (params[:page] || 1).to_i, 1 ].max
    @conflicts = @conflicts.by_priority.limit(25).offset((page - 1) * 25)

    # Stats for UI - calculate separately to avoid GROUP BY issues
    base_scope = if @sync_session
      @sync_session.sync_conflicts
    else
      SyncConflict.all
    end

    # Apply same filters as main query for stats
    base_scope = base_scope.where(status: params[:status]) if params[:status].present?
    base_scope = base_scope.where(conflict_type: params[:type]) if params[:type].present?

    @stats = {
      total: base_scope.count,
      pending: base_scope.unresolved.count,
      resolved: base_scope.resolved.count,
      by_type: base_scope.group(:conflict_type).count
    }

    respond_to do |format|
      format.html
      format.json { render json: @conflicts }
      format.turbo_stream
    end
  end

  def show
    @existing_expense = @sync_conflict.existing_expense
    @new_expense = @sync_conflict.new_expense
    @differences = @sync_conflict.field_differences
    @resolutions = @sync_conflict.conflict_resolutions.recent.limit(10)

    respond_to do |format|
      format.html
      format.json {
        render json: {
          conflict: @sync_conflict,
          existing_expense: @existing_expense,
          new_expense: @new_expense,
          differences: @differences,
          resolutions: @resolutions
        }
      }
      format.turbo_stream
    end
  end

  def resolve
    action = params[:action_type]
    options = resolve_params

    service = Services::ConflictResolutionService.new(@sync_conflict)

    if service.resolve(action, options)
      respond_to do |format|
        format.html {
          redirect_to sync_conflicts_path,
          notice: "Conflicto resuelto exitosamente"
        }
        format.json {
          render json: {
            success: true,
            conflict: @sync_conflict.reload
          }
        }
        format.turbo_stream {
          render turbo_stream: [
            turbo_stream.replace(
              "conflict_#{@sync_conflict.id}",
              partial: "sync_conflicts/conflict_row",
              locals: { conflict: @sync_conflict.reload }
            ),
            turbo_stream.prepend(
              "notifications",
              partial: "shared/toast",
              locals: {
                message: "Conflicto resuelto exitosamente",
                type: "success"
              }
            )
          ]
        }
      end
    else
      respond_to do |format|
        format.html {
          redirect_back(
            fallback_location: sync_conflict_path(@sync_conflict),
            alert: "Error al resolver conflicto: #{service.errors.join(', ')}"
          )
        }
        format.json {
          render json: {
            success: false,
            errors: service.errors
          }, status: :unprocessable_content
        }
        format.turbo_stream {
          render turbo_stream: turbo_stream.prepend(
            "notifications",
            partial: "shared/toast",
            locals: {
              message: "Error: #{service.errors.join(', ')}",
              type: "error"
            }
          )
        }
      end
    end
  end

  def bulk_resolve
    conflict_ids = params[:conflict_ids] || []
    action = params[:action_type]

    if conflict_ids.empty?
      render json: {
        success: false,
        error: "No se seleccionaron conflictos"
      }, status: :bad_request
      return
    end

    # Use first conflict to initialize service (for bulk operations)
    first_conflict = SyncConflict.find(conflict_ids.first)
    service = Services::ConflictResolutionService.new(first_conflict)

    result = service.bulk_resolve(conflict_ids, action, resolve_params)

    respond_to do |format|
      format.json {
        render json: {
          success: true,
          resolved_count: result[:resolved_count],
          failed_count: result[:failed_count],
          failed_conflicts: result[:failed_conflicts]
        }
      }
      format.turbo_stream {
        # Update each conflict row
        streams = conflict_ids.map do |id|
          conflict = SyncConflict.find_by(id: id)
          next unless conflict

          turbo_stream.replace(
            "conflict_#{id}",
            partial: "sync_conflicts/conflict_row",
            locals: { conflict: conflict }
          )
        end.compact

        # Add notification
        streams << turbo_stream.prepend(
          "notifications",
          partial: "shared/toast",
          locals: {
            message: "#{result[:resolved_count]} conflictos resueltos",
            type: "success"
          }
        )

        render turbo_stream: streams
      }
    end
  end

  def undo
    service = Services::ConflictResolutionService.new(@sync_conflict)

    if service.undo_resolution
      respond_to do |format|
        format.html {
          redirect_back(
            fallback_location: sync_conflict_path(@sync_conflict),
            notice: "Resolución deshecha exitosamente"
          )
        }
        format.json {
          render json: {
            success: true,
            conflict: @sync_conflict.reload
          }
        }
        format.turbo_stream {
          render turbo_stream: [
            turbo_stream.replace(
              "conflict_#{@sync_conflict.id}",
              partial: "sync_conflicts/conflict_row",
              locals: { conflict: @sync_conflict.reload }
            ),
            turbo_stream.prepend(
              "notifications",
              partial: "shared/toast",
              locals: {
                message: "Resolución deshecha",
                type: "info"
              }
            )
          ]
        }
      end
    else
      respond_to do |format|
        format.html {
          redirect_back(
            fallback_location: sync_conflict_path(@sync_conflict),
            alert: "Error al deshacer: #{service.errors.join(', ')}"
          )
        }
        format.json {
          render json: {
            success: false,
            errors: service.errors
          }, status: :unprocessable_content
        }
      end
    end
  end

  def preview_merge
    merge_fields = params[:merge_fields] || ActionController::Parameters.new({})

    service = Services::ConflictResolutionService.new(@sync_conflict)
    preview = service.preview_merge(merge_fields)

    render json: {
      success: true,
      preview: preview,
      changes: calculate_merge_changes(preview)
    }
  end

  private

  def set_sync_conflict
    @sync_conflict = SyncConflict.find(params[:id])
  end

  def set_sync_session
    @sync_session = SyncSession.find(params[:sync_session_id]) if params[:sync_session_id]
  end

  def resolve_params
    params.permit(
      :resolved_by,
      merge_fields: {},
      custom_data: [
        existing_expense: {},
        new_expense: {}
      ]
    )
  end

  def calculate_merge_changes(preview)
    return {} unless @sync_conflict.existing_expense && preview

    changes = {}
    @sync_conflict.existing_expense.attributes.each do |key, value|
      if preview[key] != value
        changes[key] = {
          from: value,
          to: preview[key]
        }
      end
    end
    changes
  end
end

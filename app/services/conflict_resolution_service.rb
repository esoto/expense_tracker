class ConflictResolutionService
  attr_reader :sync_conflict, :errors

  def initialize(sync_conflict)
    @sync_conflict = sync_conflict
    @errors = []
  end

  def resolve(action, options = {})
    return false unless valid_action?(action)
    return false if sync_conflict.status_resolved?

    begin
      case action
      when "keep_existing"
        resolve_keep_existing(options)
      when "keep_new"
        resolve_keep_new(options)
      when "keep_both"
        resolve_keep_both(options)
      when "merged"
        resolve_merge(options)
      when "custom"
        resolve_custom(options)
      else
        add_error("Invalid resolution action: #{action}")
        return false
      end

      true
    rescue => e
      add_error("Resolution failed: #{e.message}")
      Rails.logger.error "[ConflictResolution] Failed to resolve conflict ##{sync_conflict.id}: #{e.message}"
      false
    end
  end

  def bulk_resolve(conflict_ids, action, options = {})
    resolved_count = 0
    failed_conflicts = []

    conflicts = SyncConflict.where(id: conflict_ids, status: "pending")

    conflicts.find_each do |conflict|
      service = self.class.new(conflict)

      if service.resolve(action, options)
        resolved_count += 1
      else
        failed_conflicts << {
          id: conflict.id,
          errors: service.errors
        }
      end
    end

    {
      resolved_count: resolved_count,
      failed_count: failed_conflicts.count,
      failed_conflicts: failed_conflicts
    }
  end

  def undo_resolution
    return false unless sync_conflict.status_resolved?

    begin
      sync_conflict.undo_last_resolution!
      true
    rescue => e
      add_error("Failed to undo resolution: #{e.message}")
      false
    end
  end

  def preview_merge(merge_fields)
    # Preview what the merged expense would look like
    existing = sync_conflict.existing_expense
    new_expense = sync_conflict.new_expense

    return nil unless new_expense

    merged_attributes = existing.attributes.dup

    merge_fields.each do |field, source|
      if source == "new" && new_expense.respond_to?(field)
        merged_attributes[field] = new_expense.send(field)
      end
    end

    merged_attributes
  end

  private

  def valid_action?(action)
    %w[keep_existing keep_new keep_both merged custom].include?(action)
  end

  def resolve_keep_existing(options)
    ActiveRecord::Base.transaction do
      # Mark new expense as duplicate if it exists
      if sync_conflict.new_expense
        sync_conflict.new_expense.update!(
          status: "duplicate",
          notes: "Duplicado de gasto ##{sync_conflict.existing_expense_id}"
        )
      end

      # Update conflict
      sync_conflict.resolve!("keep_existing", options, options[:resolved_by])

      # Log the resolution
      log_resolution("keep_existing", options)
    end
  end

  def resolve_keep_new(options)
    ActiveRecord::Base.transaction do
      # Mark existing as duplicate, promote new
      sync_conflict.existing_expense.update!(
        status: "duplicate",
        notes: "Reemplazado por gasto ##{sync_conflict.new_expense_id}"
      )

      if sync_conflict.new_expense
        sync_conflict.new_expense.update!(
          status: "processed"
        )
      end

      # Update conflict
      sync_conflict.resolve!("keep_new", options, options[:resolved_by])

      # Log the resolution
      log_resolution("keep_new", options)
    end
  end

  def resolve_keep_both(options)
    ActiveRecord::Base.transaction do
      # Mark both as valid/processed
      sync_conflict.existing_expense.update!(status: "processed")

      if sync_conflict.new_expense
        sync_conflict.new_expense.update!(
          status: "processed",
          notes: "Mantenido como gasto separado"
        )
      end

      # Update conflict
      sync_conflict.resolve!("keep_both", options, options[:resolved_by])

      # Log the resolution
      log_resolution("keep_both", options)
    end
  end

  def resolve_merge(options)
    merge_fields = options[:merge_fields] || {}

    ActiveRecord::Base.transaction do
      existing = sync_conflict.existing_expense
      new_expense = sync_conflict.new_expense

      return false unless new_expense

      # Apply merged fields
      updates = {}
      merge_fields.each do |field, source|
        if source == "new" && new_expense.respond_to?(field)
          updates[field] = new_expense.send(field)
        end
      end

      existing.update!(updates) if updates.any?

      # Mark new as duplicate
      new_expense.update!(
        status: "duplicate",
        notes: "Fusionado con gasto ##{existing.id}"
      )

      # Update conflict
      sync_conflict.resolve!("merged", { merge_fields: merge_fields }, options[:resolved_by])

      # Log the resolution
      log_resolution("merged", options.merge(merge_fields: merge_fields))
    end
  end

  def resolve_custom(options)
    custom_data = options[:custom_data] || {}

    ActiveRecord::Base.transaction do
      # Apply custom updates to existing expense
      if custom_data[:existing_expense].present?
        sync_conflict.existing_expense.update!(custom_data[:existing_expense])
      end

      # Apply custom updates to new expense
      if custom_data[:new_expense].present? && sync_conflict.new_expense
        sync_conflict.new_expense.update!(custom_data[:new_expense])
      end

      # Update conflict
      sync_conflict.resolve!("custom", custom_data, options[:resolved_by])

      # Log the resolution
      log_resolution("custom", options)
    end
  end

  def log_resolution(action, options)
    Rails.logger.info "[ConflictResolution] Resolved conflict ##{sync_conflict.id} with action: #{action}"

    # Track analytics
    track_resolution_analytics(action, options)
  end

  def track_resolution_analytics(action, options)
    # In a production app, this would send to analytics service
    Rails.cache.increment("conflict_resolutions:#{action}:count")
    Rails.cache.increment("conflict_resolutions:total:count")

    if options[:resolved_by] == "system_auto"
      Rails.cache.increment("conflict_resolutions:auto:count")
    else
      Rails.cache.increment("conflict_resolutions:manual:count")
    end
  end

  def add_error(message)
    @errors << message
  end
end

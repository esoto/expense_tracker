class ConflictResolution < ApplicationRecord
  # Associations
  belongs_to :sync_conflict
  belongs_to :undone_by_resolution, class_name: "ConflictResolution", optional: true
  has_one :undoes_resolution, class_name: "ConflictResolution", foreign_key: "undone_by_resolution_id"

  # Validations
  validates :action, presence: true
  validates :action, inclusion: { in: %w[keep_existing keep_new keep_both merged custom undo] }
  validates :resolution_method, inclusion: { in: %w[manual auto bulk api] }, allow_nil: true

  # Scopes
  scope :not_undone, -> { where(undone: false) }
  scope :undone, -> { where(undone: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :manual, -> { where(resolution_method: "manual") }
  scope :automatic, -> { where(resolution_method: [ "auto", "bulk" ]) }
  scope :undoable, -> { where(undoable: true, undone: false) }

  # Instance methods
  def can_undo?
    undoable && !undone && !undo_action?
  end

  def undo_action?
    action == "undo"
  end

  def display_action
    case action
    when "keep_existing"
      "Mantener existente"
    when "keep_new"
      "Mantener nuevo"
    when "keep_both"
      "Mantener ambos"
    when "merged"
      "Fusionado"
    when "custom"
      "Personalizado"
    when "undo"
      "Deshacer"
    else
      action.humanize
    end
  end

  def display_method
    case resolution_method
    when "manual"
      "Manual"
    when "auto"
      "Automático"
    when "bulk"
      "En lote"
    when "api"
      "API"
    else
      resolution_method&.humanize || "Desconocido"
    end
  end

  def changed_fields
    return [] unless changes_made.present?

    fields = []

    if changes_made["existing_expense"].present?
      before = changes_made["existing_expense"]["before"]
      after = changes_made["existing_expense"]["after"]

      before.each_key do |field|
        if before[field] != after[field]
          fields << {
            expense: "existing",
            field: field,
            before: before[field],
            after: after[field]
          }
        end
      end
    end

    if changes_made["new_expense"].present?
      before = changes_made["new_expense"]["before"]
      after = changes_made["new_expense"]["after"]

      before.each_key do |field|
        if before[field] != after[field]
          fields << {
            expense: "new",
            field: field,
            before: before[field],
            after: after[field]
          }
        end
      end
    end

    fields
  end

  def summary
    case action
    when "keep_existing"
      "Se mantuvo el gasto existente y se marcó el nuevo como duplicado"
    when "keep_new"
      "Se mantuvo el nuevo gasto y se marcó el existente como duplicado"
    when "keep_both"
      "Se mantuvieron ambos gastos como separados"
    when "merged"
      "Se fusionaron los gastos, combinando #{changed_fields.count} campos"
    when "custom"
      "Se aplicó una resolución personalizada con #{changed_fields.count} cambios"
    when "undo"
      "Se deshizo la resolución anterior"
    else
      "Resolución aplicada"
    end
  end
end

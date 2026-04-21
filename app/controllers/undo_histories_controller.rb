# frozen_string_literal: true

# SECURITY: All undo_histories lookups are scoped to scoping_user (PR 8).
class UndoHistoriesController < ApplicationController
  before_action :set_undo_history

  # POST /undo_histories/:id/undo
  def undo
    if @undo_history.nil?
      render json: { success: false, message: "Undo record not found" }, status: :not_found
      return
    end

    if @undo_history.undoable?
      if @undo_history.undo!
        respond_to do |format|
          format.turbo_stream do
            # Refresh the expense list
            render turbo_stream: turbo_stream.replace(
              "dashboard-expenses-widget",
              partial: "expenses/dashboard_expenses",
              locals: {
                recent_expenses: fetch_recent_expenses,
                expense_view_mode: session[:dashboard_expense_view_mode] || "compact"
              }
            )
          end
          format.json do
            render json: {
              success: true,
              message: "Acción deshecha exitosamente",
              affected_count: @undo_history.affected_count
            }
          end
        end
      else
        render json: {
          success: false,
          message: "No se pudo deshacer la acción"
        }, status: :unprocessable_entity
      end
    else
      render json: {
        success: false,
        message: "Esta acción ya no se puede deshacer"
      }, status: :unprocessable_entity
    end
  end

  private

  def set_undo_history
    @undo_history = UndoHistory.for_user(scoping_user).find_by(id: params[:id])
  end

  def fetch_recent_expenses
    # Reuse the logic from ExpensesController
    Expense.includes(:category, :email_account)
           .recent
           .limit(20)
  end

  # Mirrors SyncSessionsController#scoping_user — PR 12 will wire up real auth.
  # Until then: prefer current_app_user (set by ApplicationController once the
  # session-token middleware lands), fall back to User.admin.first so the app
  # remains functional for single-user installs.
  def scoping_user
    @scoping_user ||= begin
      user = try(:current_app_user)
      unless user
        Rails.logger.warn(
          "[scoping_user] current_app_user is nil; falling back to User.admin.first " \
          "(controller: #{self.class.name})"
        )
        user = User.admin.first
      end
      user
    end
  end
end

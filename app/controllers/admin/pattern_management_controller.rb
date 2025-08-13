# frozen_string_literal: true

# Controller for pattern import, export, and analytics operations
class Admin::PatternManagementController < Admin::BaseController
  before_action :require_admin_authentication
  before_action :require_pattern_management_permission

  def import
    if params[:file].present?
      result = Services::Categorization::PatternImporter.new.import(params[:file])

      if result[:success]
        flash[:notice] = "Successfully imported #{result[:imported_count]} patterns"
      else
        flash[:alert] = "Import failed: #{result[:error]}"
      end
    else
      flash[:alert] = "Please select a file to import"
    end

    redirect_to admin_patterns_path
  end

  def export
    respond_to do |format|
      format.csv do
        csv_data = Services::Categorization::PatternExporter.new.export_to_csv
        send_data csv_data,
                  filename: "patterns_#{Date.current.strftime('%Y%m%d')}.csv",
                  type: "text/csv"
      end
    end
  end

  def statistics
    @stats = Services::Categorization::PatternAnalytics.new.generate_statistics

    respond_to do |format|
      format.json { render json: @stats }
    end
  end

  def performance
    @performance_data = Services::Categorization::PatternAnalytics.new.performance_over_time

    respond_to do |format|
      format.json { render json: @performance_data }
    end
  end

  def toggle_active
    @pattern = CategorizationPattern.find(params[:id])
    @pattern.update!(active: !@pattern.active)

    respond_to do |format|
      format.turbo_stream { render "admin/patterns/toggle_active" }
      format.html { redirect_to admin_patterns_path }
    end
  end

  private

  def require_pattern_management_permission
    # Pattern management permission check
    true
  end
end


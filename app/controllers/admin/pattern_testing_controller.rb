# frozen_string_literal: true

# Controller for pattern testing and management operations
class Admin::PatternTestingController < Admin::BaseController
  before_action :require_admin_authentication
  before_action :require_pattern_management_permission

  def test
    render "admin/patterns/test"
  end

  def test_pattern
    @matching_patterns = Services::Categorization::PatternMatcher.new.find_matching_patterns(
      merchant_name: params[:merchant_name],
      description: params[:description],
      amount: params[:amount]&.to_f
    )

    respond_to do |format|
      format.turbo_stream { render "admin/patterns/test_pattern" }
    end
  end

  def test_single
    @pattern = CategorizationPattern.find(params[:id])

    test_expense = OpenStruct.new(
      merchant_name: params[:merchant_name],
      description: params[:description],
      amount: params[:amount]&.to_f
    )

    @match_result = @pattern.matches?(test_expense)

    respond_to do |format|
      format.turbo_stream { render "admin/patterns/test_single" }
    end
  end

  private

  def require_pattern_management_permission
    # Pattern management permission check
    true
  end
end

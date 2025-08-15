# frozen_string_literal: true

# Controller for pattern testing and management operations
class Admin::PatternTestingController < Admin::BaseController
  before_action :require_pattern_management_permission, except: [ :test ]

  def test
    @patterns = CategorizationPattern.active.includes(:category)
    render "admin/patterns/test"
  end

  def test_pattern
    tester = Patterns::PatternTester.new(test_pattern_params)

    if tester.test
      @matching_patterns = tester.categories_with_confidence
      @test_expense = tester.test_expense

      respond_to do |format|
        format.turbo_stream { render "admin/patterns/test_pattern" }
        format.json { render json: { matches: @matching_patterns } }
      end
    else
      respond_to do |format|
        format.turbo_stream { render_test_error(tester.errors.full_messages) }
        format.json { render json: { errors: tester.errors }, status: :unprocessable_content }
      end
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

  # Remove this method - it's already defined in AdminAuthentication concern

  def test_pattern_params
    params.permit(:description, :merchant_name, :amount, :transaction_date)
  end

  def render_test_error(errors)
    render turbo_stream: turbo_stream.replace(
      "test_results",
      partial: "shared/errors",
      locals: { errors: errors }
    )
  end
end

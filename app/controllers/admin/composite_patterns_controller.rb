# frozen_string_literal: true

require "ostruct"

module Admin
  # Controller for managing composite categorization patterns
  class CompositePatternsController < BaseController
    before_action :set_composite_pattern, only: [ :show, :edit, :update, :destroy, :toggle_active, :test ]
    before_action :load_resources, only: [ :new, :edit, :create, :update ]

    # GET /admin/composite_patterns
    def index
      @composite_patterns = CompositePattern.includes(:category)
                                           .order(created_at: :desc)
                                           .page(params[:page])
                                           .per(20)
    end

    # GET /admin/composite_patterns/:id
    def show
      @component_patterns = @composite_pattern.component_patterns.includes(:category)
    end

    # GET /admin/composite_patterns/new
    def new
      @composite_pattern = CompositePattern.new(
        operator: "AND",
        confidence_weight: CompositePattern::DEFAULT_CONFIDENCE_WEIGHT,
        active: true,
        user_created: true
      )
    end

    # GET /admin/composite_patterns/:id/edit
    def edit
      @selected_patterns = @composite_pattern.component_patterns
    end

    # POST /admin/composite_patterns
    def create
      @composite_pattern = CompositePattern.new(composite_pattern_params)
      @composite_pattern.user_created = true
      @composite_pattern.usage_count = 0
      @composite_pattern.success_count = 0
      @composite_pattern.success_rate = 0.0

      if @composite_pattern.save
        redirect_to admin_composite_pattern_path(@composite_pattern),
                    notice: "Composite pattern was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /admin/composite_patterns/:id
    def update
      if @composite_pattern.update(composite_pattern_params)
        redirect_to admin_composite_pattern_path(@composite_pattern),
                    notice: "Composite pattern was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /admin/composite_patterns/:id
    def destroy
      @composite_pattern.destroy
      redirect_to admin_composite_patterns_path,
                  notice: "Composite pattern was successfully deleted."
    end

    # POST /admin/composite_patterns/:id/toggle_active
    def toggle_active
      @composite_pattern.update!(active: !@composite_pattern.active)

      respond_to do |format|
        format.html { redirect_to admin_composite_patterns_path }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              dom_id(@composite_pattern, :row),
              partial: "admin/composite_patterns/composite_pattern_row",
              locals: { composite_pattern: @composite_pattern }
            ),
            turbo_stream.replace(
              "flash",
              partial: "shared/flash",
              locals: {
                notice: @composite_pattern.active? ? "Composite pattern activated" : "Composite pattern deactivated"
              }
            )
          ]
        end
      end
    end

    # GET /admin/composite_patterns/:id/test
    def test
      test_expense = OpenStruct.new(
        description: params[:description],
        merchant_name: params[:merchant_name],
        amount: params[:amount]&.to_f,
        transaction_date: params[:transaction_date]&.to_datetime || DateTime.current
      )

      @matches = @composite_pattern.matches?(test_expense)
      @confidence = @matches ? @composite_pattern.effective_confidence : 0

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "composite_test_result",
            partial: "admin/composite_patterns/test_result",
            locals: {
              matches: @matches,
              confidence: @confidence,
              composite_pattern: @composite_pattern
            }
          )
        end
      end
    end

    private

    def set_composite_pattern
      @composite_pattern = CompositePattern.find(params[:id])
    end

    def load_resources
      @categories = Category.order(:name)
      @available_patterns = CategorizationPattern.active
                                                 .includes(:category)
                                                 .order(:pattern_type, :pattern_value)
    end

    def composite_pattern_params
      params.require(:composite_pattern).permit(
        :name,
        :operator,
        :category_id,
        :confidence_weight,
        :active,
        pattern_ids: [],
        conditions: {}
      )
    end
  end
end

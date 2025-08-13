# frozen_string_literal: true

module Api
  module V1
    # API controller for managing categorization patterns
    class PatternsController < BaseController
      include ApiCaching

      before_action :set_pattern, only: [ :show, :update, :destroy ]
      after_action :set_cache_headers_for_read, only: [ :index, :show ]

      # GET /api/v1/patterns
      def index
        patterns = CategorizationPattern.includes(:category)

        # Apply filters
        patterns = filter_patterns(patterns)

        # Apply sorting
        patterns = sort_patterns(patterns)

        # Paginate results
        patterns = paginate(patterns)

        # Handle conditional GET with ETag
        handle_conditional_get(patterns)

        render_success({
          patterns: serialize_patterns(patterns),
          meta: pagination_meta(patterns)
        })
      end

      # GET /api/v1/patterns/:id
      def show
        # Handle conditional GET with ETag
        fresh_when(@pattern, public: true)

        render_success({
          pattern: serialize_pattern(@pattern)
        })
      end

      # POST /api/v1/patterns
      def create
        pattern = CategorizationPattern.new(pattern_params)
        pattern.user_created = true
        pattern.confidence_weight ||= 1.0

        if pattern.save
          render_success(
            { pattern: serialize_pattern(pattern) },
            status: :created
          )
        else
          render_error(
            "Failed to create pattern",
            pattern.errors.full_messages
          )
        end
      end

      # PATCH /api/v1/patterns/:id
      def update
        if @pattern.update(update_pattern_params)
          render_success({
            pattern: serialize_pattern(@pattern)
          })
        else
          render_error(
            "Failed to update pattern",
            @pattern.errors.full_messages
          )
        end
      end

      # DELETE /api/v1/patterns/:id
      def destroy
        # Soft delete by deactivating
        if @pattern.update(active: false)
          render_success({
            message: "Pattern deactivated successfully"
          })
        else
          render_error(
            "Failed to deactivate pattern",
            @pattern.errors.full_messages
          )
        end
      end

      private

      def set_pattern
        @pattern = CategorizationPattern.find(params[:id])
      end

      def pattern_params
        params.require(:pattern).permit(
          :pattern_type,
          :pattern_value,
          :category_id,
          :confidence_weight,
          :active,
          metadata: {}
        )
      end

      def update_pattern_params
        params.require(:pattern).permit(
          :pattern_value,
          :confidence_weight,
          :active,
          metadata: {}
        )
      end

      def filter_params
        params.permit(
          :pattern_type,
          :category_id,
          :active,
          :user_created,
          :min_success_rate,
          :min_usage_count
        )
      end

      def filter_patterns(patterns)
        patterns = patterns.where(pattern_type: filter_params[:pattern_type]) if filter_params[:pattern_type].present?
        patterns = patterns.where(category_id: filter_params[:category_id]) if filter_params[:category_id].present?
        patterns = patterns.where(active: filter_params[:active]) if filter_params.key?(:active)
        patterns = patterns.where(user_created: filter_params[:user_created]) if filter_params.key?(:user_created)

        if filter_params[:min_success_rate].present?
          patterns = patterns.where("success_rate >= ?", filter_params[:min_success_rate].to_f)
        end

        if filter_params[:min_usage_count].present?
          patterns = patterns.where("usage_count >= ?", filter_params[:min_usage_count].to_i)
        end

        patterns
      end

      def sort_patterns(patterns)
        case params[:sort_by]
        when "success_rate"
          patterns.order(success_rate: sort_direction)
        when "usage_count"
          patterns.order(usage_count: sort_direction)
        when "created_at"
          patterns.order(created_at: sort_direction)
        when "pattern_type"
          patterns.order(pattern_type: sort_direction)
        else
          patterns.ordered_by_success
        end
      end

      def sort_direction
        %w[asc desc].include?(params[:sort_direction]&.downcase) ? params[:sort_direction].downcase : "desc"
      end

      def serialize_patterns(patterns)
        Api::V1::PatternSerializer.collection(patterns, include_metadata: params[:include_metadata] == "true")
      end

      def serialize_pattern(pattern)
        Api::V1::PatternSerializer.new(pattern, include_metadata: true).as_json
      end

      def pagination_meta(collection)
        {
          current_page: collection.current_page,
          total_pages: collection.total_pages,
          total_count: collection.total_count,
          per_page: collection.limit_value,
          next_page: collection.next_page,
          prev_page: collection.prev_page
        }
      end

      def set_cache_headers_for_read
        set_cache_headers(max_age: 5.minutes.to_i, public: true)
      end
    end
  end
end

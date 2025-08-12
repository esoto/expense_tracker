### Task 2.1: Pattern API Endpoints
**Priority**: Critical  
**Estimated Hours**: 6  
**Dependencies**: Tasks 1.1-1.6  

#### Description
Create RESTful API endpoints for pattern management and categorization.

#### Acceptance Criteria
- [ ] POST /api/v1/categorization/suggest - Returns category suggestion
- [ ] GET /api/v1/patterns - Lists patterns with pagination
- [ ] POST /api/v1/patterns - Creates new pattern
- [ ] PATCH /api/v1/patterns/:id - Updates pattern
- [ ] DELETE /api/v1/patterns/:id - Soft deletes pattern
- [ ] POST /api/v1/categorization/feedback - Records user feedback
- [ ] API documentation with examples
- [ ] Rate limiting implemented (100 req/min)
- [ ] Authentication via API tokens

#### Technical Implementation
```ruby
# app/controllers/api/v1/patterns_controller.rb
class Api::V1::PatternsController < Api::V1::BaseController
  before_action :authenticate_api_token!
  before_action :set_pattern, only: [:show, :update, :destroy]
  
  def index
    @patterns = CategorizationPattern
      .active
      .includes(:category)
      .page(params[:page])
      .per(params[:per_page] || 25)
    
    render json: PatternSerializer.new(@patterns, {
      meta: pagination_meta(@patterns)
    })
  end
  
  def create
    @pattern = CategorizationPattern.new(pattern_params)
    
    if @pattern.save
      PatternCacheInvalidator.perform_async
      render json: PatternSerializer.new(@pattern), status: :created
    else
      render json: { errors: @pattern.errors }, status: :unprocessable_entity
    end
  end
  
  def suggest
    expense_data = suggestion_params
    engine = Categorization::PatternEngine.new
    
    result = engine.categorize_from_data(expense_data)
    
    render json: {
      category: CategorySerializer.new(result.category),
      confidence: result.confidence,
      explanation: result.explanation,
      alternatives: result.alternatives.map { |alt|
        {
          category: CategorySerializer.new(alt.category),
          confidence: alt.confidence
        }
      }
    }
  end
  
  private
  
  def pattern_params
    params.require(:pattern).permit(
      :pattern_type, :pattern_value, :category_id,
      :confidence_weight, metadata: {}
    )
  end
end
```

#### Testing Requirements
```ruby
# spec/requests/api/v1/patterns_spec.rb
RSpec.describe "Patterns API" do
  let(:api_token) { create(:api_token) }
  let(:headers) { { 'X-API-Token' => api_token.token } }
  
  describe "POST /api/v1/patterns" do
    it "creates pattern with valid data" do
      post "/api/v1/patterns", 
           params: { pattern: valid_attributes },
           headers: headers
      
      expect(response).to have_http_status(:created)
      expect(json_response['data']['attributes']['pattern_value'])
        .to eq(valid_attributes[:pattern_value])
    end
    
    it "invalidates cache after creation" do
      expect(PatternCacheInvalidator).to receive(:perform_async)
      
      post "/api/v1/patterns",
           params: { pattern: valid_attributes },
           headers: headers
    end
  end
end
```

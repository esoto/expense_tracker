# Option 3: AI Foundation Tasks - Hybrid Intelligence

## Phase 1: AI Infrastructure Setup (Week 1-2)

### Task AI-1.1: Vector Database Setup
**Priority**: Critical  
**Estimated Hours**: 6  
**Dependencies**: Options 1 & 2 completion  

#### Description
Install and configure PostgreSQL pgvector extension for embedding storage and similarity search.

#### Acceptance Criteria
- [ ] pgvector extension installed and enabled
- [ ] Embedding tables created with proper dimensions
- [ ] Vector indexes configured for performance
- [ ] Similarity search functions implemented
- [ ] Performance: < 50ms for 1000 vector search
- [ ] Support for 1536-dimension OpenAI embeddings
- [ ] Backup and recovery procedures documented

#### Technical Implementation
```ruby
# db/migrate/[timestamp]_setup_vector_database.rb
class SetupVectorDatabase < ActiveRecord::Migration[8.0]
  def up
    # Enable pgvector extension
    enable_extension 'vector' unless extension_enabled?('vector')
    
    # Create expense embeddings table
    create_table :expense_embeddings do |t|
      t.references :expense, null: false, foreign_key: true
      t.column :embedding, :vector, limit: 1536
      t.string :model_version, default: 'text-embedding-ada-002'
      t.float :generation_cost
      t.boolean :used_for_training, default: false
      t.timestamps
      
      t.index :expense_id, unique: true
    end
    
    # Create category embeddings (centroids)
    create_table :category_embeddings do |t|
      t.references :category, null: false, foreign_key: true
      t.column :embedding, :vector, limit: 1536
      t.integer :example_count, default: 0
      t.float :variance # Spread of examples
      t.float :confidence_threshold
      t.json :metadata
      t.timestamps
      
      t.index :category_id, unique: true
    end
    
    # Create embedding cache for common queries
    create_table :embedding_caches do |t|
      t.string :cache_key, null: false
      t.column :embedding, :vector, limit: 1536
      t.datetime :expires_at
      t.integer :hit_count, default: 0
      t.timestamps
      
      t.index :cache_key, unique: true
      t.index :expires_at
    end
    
    # Add vector indexes for similarity search
    add_index :expense_embeddings, :embedding, 
              using: :ivfflat, 
              opclass: :vector_cosine_ops,
              with: { lists: 100 }
    
    add_index :category_embeddings, :embedding,
              using: :ivfflat,
              opclass: :vector_cosine_ops,
              with: { lists: 50 }
    
    # Create similarity search function
    execute <<-SQL
      CREATE OR REPLACE FUNCTION find_similar_expenses(
        query_embedding vector(1536),
        limit_count integer DEFAULT 10
      )
      RETURNS TABLE(
        expense_id bigint,
        similarity float
      ) AS $$
      BEGIN
        RETURN QUERY
        SELECT 
          e.expense_id,
          1 - (e.embedding <=> query_embedding) as similarity
        FROM expense_embeddings e
        ORDER BY e.embedding <=> query_embedding
        LIMIT limit_count;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end
  
  def down
    drop_table :embedding_caches
    drop_table :category_embeddings
    drop_table :expense_embeddings
    disable_extension 'vector'
  end
end
```

#### Model Implementation
```ruby
# app/models/expense_embedding.rb
class ExpenseEmbedding < ApplicationRecord
  belongs_to :expense
  
  validates :embedding, presence: true
  validates :expense_id, uniqueness: true
  
  scope :with_expenses, -> { includes(:expense) }
  
  def self.find_similar(embedding, limit: 10)
    sql = <<-SQL
      SELECT expense_id, 
             1 - (embedding <=> ?::vector) as similarity
      FROM expense_embeddings
      ORDER BY embedding <=> ?::vector
      LIMIT ?
    SQL
    
    sanitized = sanitize_sql_array([sql, embedding, embedding, limit])
    result = connection.execute(sanitized)
    
    result.map do |row|
      {
        expense: Expense.find(row['expense_id']),
        similarity: row['similarity'].to_f
      }
    end
  end
  
  def similarity_to(other_embedding)
    return 0.0 unless embedding && other_embedding
    
    # Cosine similarity
    1 - cosine_distance(embedding, other_embedding)
  end
  
  private
  
  def cosine_distance(vec1, vec2)
    # PostgreSQL's <=> operator calculates cosine distance
    sql = "SELECT ?::vector <=> ?::vector as distance"
    result = self.class.connection.execute(
      self.class.sanitize_sql_array([sql, vec1, vec2])
    )
    result.first['distance'].to_f
  end
end
```

---

### Task AI-1.2: LLM Client Service
**Priority**: Critical  
**Estimated Hours**: 8  
**Dependencies**: Task AI-1.1  

#### Description
Implement robust client for OpenAI/Anthropic APIs with error handling and cost tracking.

#### Acceptance Criteria
- [ ] Support for multiple LLM providers
- [ ] Retry logic with exponential backoff
- [ ] Rate limiting (3000 tokens/min)
- [ ] Cost tracking per request
- [ ] Response caching with Redis
- [ ] PII redaction before API calls
- [ ] Streaming support for real-time UI
- [ ] Circuit breaker for API failures
- [ ] Comprehensive error handling

#### Technical Implementation
```ruby
# app/services/ai/llm_client.rb
module AI
  class LLMClient
    include Retryable
    
    PROVIDERS = {
      openai: OpenAIProvider,
      anthropic: AnthropicProvider
    }.freeze
    
    def initialize(provider: :openai)
      @provider = PROVIDERS[provider].new
      @rate_limiter = RateLimiter.new(
        max_tokens_per_minute: 3000,
        max_requests_per_minute: 60
      )
      @cost_tracker = CostTracker.new
      @cache = ResponseCache.new
      @sanitizer = PIISanitizer.new
      @circuit_breaker = CircuitBreaker.new(
        failure_threshold: 5,
        timeout: 30.seconds
      )
    end
    
    def categorize(expense, options = {})
      # Check circuit breaker
      return fallback_categorization(expense) unless @circuit_breaker.allow_request?
      
      # Sanitize input
      sanitized_data = @sanitizer.sanitize_expense(expense)
      
      # Check cache
      cache_key = generate_cache_key(sanitized_data)
      if cached = @cache.get(cache_key)
        @cost_tracker.record_cache_hit
        return cached
      end
      
      # Rate limiting
      @rate_limiter.wait_if_needed
      
      # Build prompt
      prompt = build_categorization_prompt(sanitized_data, options)
      
      # Make API call with retry
      response = retryable(times: 3, on: [OpenAI::Error, Net::ReadTimeout]) do
        @circuit_breaker.record_attempt do
          call_api(prompt, options)
        end
      end
      
      # Track costs
      @cost_tracker.record(
        provider: @provider.name,
        model: options[:model] || 'gpt-3.5-turbo',
        input_tokens: response[:usage][:prompt_tokens],
        output_tokens: response[:usage][:completion_tokens]
      )
      
      # Parse and cache response
      result = parse_response(response)
      @cache.set(cache_key, result, expires_in: 1.hour)
      
      result
    rescue => e
      Rails.logger.error "LLM categorization failed: #{e.message}"
      @circuit_breaker.record_failure
      fallback_categorization(expense)
    end
    
    def generate_embedding(text, options = {})
      # Sanitize text
      sanitized = @sanitizer.sanitize_text(text)
      
      # Check cache
      cache_key = "embedding:#{Digest::SHA256.hexdigest(sanitized)}"
      if cached = @cache.get(cache_key)
        return cached
      end
      
      # Rate limiting
      @rate_limiter.wait_if_needed
      
      # Generate embedding
      response = @provider.create_embedding(
        input: sanitized,
        model: options[:model] || 'text-embedding-ada-002'
      )
      
      embedding = response['data'][0]['embedding']
      
      # Track costs
      @cost_tracker.record_embedding(
        tokens: response['usage']['total_tokens']
      )
      
      # Cache result
      @cache.set(cache_key, embedding, expires_in: 24.hours)
      
      embedding
    end
    
    private
    
    def call_api(prompt, options)
      @provider.create_chat_completion(
        model: options[:model] || 'gpt-3.5-turbo',
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: prompt }
        ],
        temperature: options[:temperature] || 0.3,
        max_tokens: options[:max_tokens] || 150,
        response_format: { type: 'json_object' }
      )
    end
    
    def build_categorization_prompt(expense_data, options)
      categories = options[:categories] || Category.active.pluck(:id, :name)
      
      <<~PROMPT
        Categorize this expense:
        
        Merchant: #{expense_data[:merchant]}
        Description: #{expense_data[:description]}
        Amount: #{expense_data[:amount]}
        Date: #{expense_data[:date]}
        
        Available categories:
        #{format_categories(categories)}
        
        Return JSON with:
        - category_id: chosen category ID
        - confidence: 0.0 to 1.0
        - reasoning: brief explanation
        - alternative_id: second choice (optional)
      PROMPT
    end
    
    def system_prompt
      <<~PROMPT
        You are a financial categorization expert specializing in expense classification.
        You understand Spanish and English transactions from Costa Rican banks.
        Always return valid JSON responses.
        Be concise but accurate in your reasoning.
      PROMPT
    end
    
    def fallback_categorization(expense)
      # Fall back to ML model
      ml_result = ML::Classifier.new.categorize(expense)
      
      {
        category_id: ml_result.category_id,
        confidence: ml_result.confidence * 0.8, # Reduce confidence
        reasoning: "Categorized using ML model (LLM unavailable)",
        method: 'ml_fallback'
      }
    end
  end
  
  # app/services/ai/pii_sanitizer.rb
  class PIISanitizer
    # Patterns for sensitive data
    PATTERNS = {
      email: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/,
      phone: /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/,
      ssn: /\b\d{3}-\d{2}-\d{4}\b/,
      credit_card: /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,
      account: /\b\d{8,12}\b/
    }.freeze
    
    def sanitize_expense(expense)
      {
        merchant: sanitize_text(expense.merchant_name),
        description: sanitize_text(expense.description),
        amount: expense.amount.round(2),
        date: expense.transaction_date.to_s,
        bank: expense.email_account&.bank_name
      }
    end
    
    def sanitize_text(text)
      return '' if text.blank?
      
      sanitized = text.dup
      
      PATTERNS.each do |type, pattern|
        sanitized.gsub!(pattern) do |match|
          "[REDACTED_#{type.upcase}]"
        end
      end
      
      sanitized
    end
  end
  
  # app/services/ai/cost_tracker.rb
  class CostTracker
    PRICING = {
      'gpt-3.5-turbo' => { input: 0.0015, output: 0.002 }, # per 1k tokens
      'gpt-4' => { input: 0.03, output: 0.06 },
      'text-embedding-ada-002' => { input: 0.0001 }
    }.freeze
    
    def initialize
      @redis = Redis::Namespace.new('ai_costs', redis: Redis.current)
    end
    
    def record(provider:, model:, input_tokens:, output_tokens:)
      cost = calculate_cost(model, input_tokens, output_tokens)
      
      # Track daily costs
      today = Date.current.to_s
      @redis.incrbyfloat("daily:#{today}", cost)
      
      # Track monthly costs
      month = Date.current.strftime('%Y-%m')
      @redis.incrbyfloat("monthly:#{month}", cost)
      
      # Track by model
      @redis.incrbyfloat("model:#{model}", cost)
      
      # Check budget limits
      check_budget_limits
      
      cost
    end
    
    def daily_cost
      @redis.get("daily:#{Date.current}").to_f
    end
    
    def monthly_cost
      @redis.get("monthly:#{Date.current.strftime('%Y-%m')}").to_f
    end
    
    def within_budget?
      daily_cost < daily_limit && monthly_cost < monthly_limit
    end
    
    private
    
    def calculate_cost(model, input_tokens, output_tokens)
      pricing = PRICING[model]
      return 0 unless pricing
      
      input_cost = (input_tokens / 1000.0) * pricing[:input]
      output_cost = (output_tokens / 1000.0) * pricing[:output] if pricing[:output]
      
      input_cost + (output_cost || 0)
    end
    
    def check_budget_limits
      if daily_cost > daily_limit * 0.8
        AlertService.notify("AI costs at 80% of daily limit: $#{daily_cost.round(2)}")
      end
      
      if monthly_cost > monthly_limit * 0.8
        AlertService.notify("AI costs at 80% of monthly limit: $#{monthly_cost.round(2)}")
      end
    end
    
    def daily_limit
      ENV.fetch('AI_DAILY_COST_LIMIT', '5.0').to_f
    end
    
    def monthly_limit
      ENV.fetch('AI_MONTHLY_COST_LIMIT', '10.0').to_f
    end
  end
end
```

---

### Task AI-1.3: Embedding Generation Service
**Priority**: Critical  
**Estimated Hours**: 6  
**Dependencies**: Task AI-1.2  

#### Description
Service to generate and manage embedding vectors for expenses and categories.

#### Acceptance Criteria
- [ ] Generate embeddings using OpenAI API
- [ ] Batch processing for efficiency (100 items/batch)
- [ ] Embedding versioning support
- [ ] Cache frequently used embeddings
- [ ] Background job for batch generation
- [ ] Progress tracking for large batches
- [ ] Cost optimization through batching
- [ ] Handle API failures gracefully

#### Technical Implementation
```ruby
# app/services/ai/embedding_generator.rb
module AI
  class EmbeddingGenerator
    include Sidekiq::Worker
    
    BATCH_SIZE = 100
    MODEL = 'text-embedding-ada-002'
    DIMENSION = 1536
    
    def initialize
      @client = LLMClient.new
      @cache = EmbeddingCache.new
      @progress_tracker = ProgressTracker.new
    end
    
    def generate_for_expense(expense)
      # Check if embedding exists
      return expense.expense_embedding if expense.expense_embedding.present?
      
      # Generate text representation
      text = expense_to_text(expense)
      
      # Generate embedding
      embedding = @client.generate_embedding(text)
      
      # Store in database
      ExpenseEmbedding.create!(
        expense: expense,
        embedding: embedding,
        model_version: MODEL,
        generation_cost: calculate_cost(text.length)
      )
    rescue => e
      Rails.logger.error "Failed to generate embedding for expense #{expense.id}: #{e.message}"
      nil
    end
    
    def batch_generate(expenses)
      total = expenses.size
      processed = 0
      
      expenses.each_slice(BATCH_SIZE) do |batch|
        # Update progress
        @progress_tracker.update(processed, total)
        
        # Process batch
        process_batch(batch)
        
        processed += batch.size
        
        # Rate limiting pause
        sleep(1) if processed < total
      end
      
      @progress_tracker.complete
    end
    
    def generate_category_embeddings
      Category.find_each do |category|
        generate_category_embedding(category)
      end
    end
    
    def generate_category_embedding(category)
      # Get example expenses for this category
      examples = category.expenses
                         .where.not(id: ExpenseEmbedding.select(:expense_id))
                         .limit(100)
      
      return if examples.empty?
      
      # Generate embeddings for examples
      embeddings = examples.map do |expense|
        generate_for_expense(expense)&.embedding
      end.compact
      
      return if embeddings.empty?
      
      # Calculate centroid
      centroid = calculate_centroid(embeddings)
      
      # Calculate variance (spread)
      variance = calculate_variance(embeddings, centroid)
      
      # Store or update
      category_embedding = CategoryEmbedding.find_or_initialize_by(
        category: category
      )
      
      category_embedding.update!(
        embedding: centroid,
        example_count: embeddings.size,
        variance: variance,
        confidence_threshold: calculate_confidence_threshold(variance)
      )
    end
    
    private
    
    def expense_to_text(expense)
      parts = []
      
      # Add merchant info
      parts << "Merchant: #{expense.merchant_name}" if expense.merchant_name.present?
      
      # Add description
      parts << "Description: #{expense.description}" if expense.description.present?
      
      # Add amount context
      parts << "Amount: #{expense.amount} #{expense.currency}"
      
      # Add temporal context
      parts << "Date: #{expense.transaction_date.strftime('%A, %B %d')}"
      
      # Add bank context
      if expense.email_account
        parts << "Bank: #{expense.email_account.bank_name}"
      end
      
      # Combine with context prefix
      "Financial transaction: #{parts.join('. ')}"
    end
    
    def process_batch(expenses)
      # Prepare texts
      texts = expenses.map { |e| expense_to_text(e) }
      
      # Generate embeddings in batch
      embeddings = @client.batch_generate_embeddings(texts)
      
      # Store results
      expenses.zip(embeddings).each do |expense, embedding|
        next if embedding.nil?
        
        ExpenseEmbedding.create!(
          expense: expense,
          embedding: embedding,
          model_version: MODEL
        )
      rescue => e
        Rails.logger.error "Failed to store embedding: #{e.message}"
      end
    end
    
    def calculate_centroid(embeddings)
      return embeddings.first if embeddings.size == 1
      
      # Calculate mean for each dimension
      dimensions = embeddings.first.size
      
      centroid = dimensions.times.map do |i|
        values = embeddings.map { |e| e[i] }
        values.sum / values.size.to_f
      end
      
      # Normalize to unit vector
      normalize_vector(centroid)
    end
    
    def calculate_variance(embeddings, centroid)
      return 0.0 if embeddings.size <= 1
      
      # Calculate average distance from centroid
      distances = embeddings.map do |embedding|
        euclidean_distance(embedding, centroid)
      end
      
      distances.sum / distances.size.to_f
    end
    
    def normalize_vector(vector)
      magnitude = Math.sqrt(vector.map { |v| v**2 }.sum)
      return vector if magnitude.zero?
      
      vector.map { |v| v / magnitude }
    end
    
    def euclidean_distance(vec1, vec2)
      Math.sqrt(
        vec1.zip(vec2).map { |a, b| (a - b)**2 }.sum
      )
    end
    
    def calculate_confidence_threshold(variance)
      # Higher variance = lower confidence threshold
      # Lower variance = higher confidence threshold
      base_threshold = 0.85
      
      if variance < 0.1
        base_threshold
      elsif variance < 0.2
        base_threshold - 0.05
      elsif variance < 0.3
        base_threshold - 0.10
      else
        base_threshold - 0.15
      end
    end
  end
end

# app/jobs/embedding_generation_job.rb
class EmbeddingGenerationJob < ApplicationJob
  queue_as :ai_processing
  
  def perform(expense_ids)
    expenses = Expense.where(id: expense_ids)
                      .includes(:expense_embedding)
                      .where(expense_embeddings: { id: nil })
    
    generator = AI::EmbeddingGenerator.new
    generator.batch_generate(expenses)
  end
end
```

---

### Task AI-1.4: Semantic Search Implementation
**Priority**: High  
**Estimated Hours**: 5  
**Dependencies**: Tasks AI-1.1, AI-1.3  

#### Description
Implement semantic similarity search using vector embeddings.

#### Acceptance Criteria
- [ ] Find N most similar expenses
- [ ] Hybrid search (semantic + keyword)
- [ ] Filter by date, amount, category
- [ ] Similarity threshold configuration
- [ ] Performance: < 100ms for 10k vectors
- [ ] Result ranking and scoring
- [ ] Search result caching

#### Technical Implementation
```ruby
# app/services/ai/semantic_search.rb
module AI
  class SemanticSearch
    def initialize
      @embedding_generator = EmbeddingGenerator.new
      @cache = SearchCache.new
    end
    
    def search_similar_expenses(expense, options = {})
      # Generate or retrieve embedding
      embedding = get_embedding(expense)
      return [] unless embedding
      
      # Build search query
      query = build_search_query(embedding, options)
      
      # Check cache
      cache_key = generate_cache_key(query)
      if cached = @cache.get(cache_key)
        return cached
      end
      
      # Execute search
      results = execute_vector_search(query)
      
      # Apply additional filters
      results = apply_filters(results, options)
      
      # Rank and score
      ranked_results = rank_results(results, expense)
      
      # Cache results
      @cache.set(cache_key, ranked_results, expires_in: 5.minutes)
      
      ranked_results
    end
    
    def find_category_matches(expense, threshold: 0.7)
      embedding = get_embedding(expense)
      return [] unless embedding
      
      # Find similar category centroids
      CategoryEmbedding
        .select(
          "category_embeddings.*",
          "1 - (embedding <=> '#{sanitize_vector(embedding)}') as similarity"
        )
        .where("1 - (embedding <=> '#{sanitize_vector(embedding)}') > ?", threshold)
        .order("embedding <=> '#{sanitize_vector(embedding)}'")
        .limit(5)
        .map do |ce|
          {
            category: ce.category,
            similarity: ce.similarity,
            confidence: calculate_confidence(ce.similarity, ce.variance)
          }
        end
    end
    
    def hybrid_search(text_query, expense_filter = {})
      # Text search using trigrams
      text_results = text_search(text_query)
      
      # Semantic search if we have enough context
      semantic_results = if text_query.length > 10
        embedding = @embedding_generator.generate_embedding(text_query)
        vector_search(embedding)
      else
        []
      end
      
      # Combine results
      combine_search_results(text_results, semantic_results)
    end
    
    private
    
    def get_embedding(expense)
      if expense.is_a?(Expense)
        expense.expense_embedding&.embedding || 
          @embedding_generator.generate_for_expense(expense)&.embedding
      else
        # It's already an embedding vector
        expense
      end
    end
    
    def build_search_query(embedding, options)
      base_query = ExpenseEmbedding
        .joins(:expense)
        .select(
          "expense_embeddings.*",
          "expenses.*",
          "1 - (expense_embeddings.embedding <=> '#{sanitize_vector(embedding)}') as similarity"
        )
      
      # Apply date filters
      if options[:date_from]
        base_query = base_query.where('expenses.transaction_date >= ?', options[:date_from])
      end
      
      if options[:date_to]
        base_query = base_query.where('expenses.transaction_date <= ?', options[:date_to])
      end
      
      # Apply amount filters
      if options[:amount_range]
        base_query = base_query.where(
          expenses: { amount: options[:amount_range] }
        )
      end
      
      # Apply category filter
      if options[:category_id]
        base_query = base_query.where(expenses: { category_id: options[:category_id] })
      end
      
      base_query
    end
    
    def execute_vector_search(query)
      limit = query[:limit] || 10
      threshold = query[:threshold] || 0.5
      
      query
        .where("1 - (expense_embeddings.embedding <=> '#{sanitize_vector(query[:embedding])}') > ?", threshold)
        .order("expense_embeddings.embedding <=> '#{sanitize_vector(query[:embedding])}'")
        .limit(limit)
    end
    
    def rank_results(results, reference_expense)
      results.map do |result|
        expense = result.expense
        
        # Calculate composite score
        score = calculate_composite_score(
          similarity: result.similarity,
          amount_similarity: calculate_amount_similarity(expense.amount, reference_expense.amount),
          date_proximity: calculate_date_proximity(expense.transaction_date, reference_expense.transaction_date),
          merchant_match: calculate_merchant_similarity(expense.merchant_name, reference_expense.merchant_name)
        )
        
        {
          expense: expense,
          similarity: result.similarity,
          composite_score: score,
          explanation: generate_explanation(expense, reference_expense, result.similarity)
        }
      end.sort_by { |r| -r[:composite_score] }
    end
    
    def calculate_composite_score(similarity:, amount_similarity:, date_proximity:, merchant_match:)
      weights = {
        similarity: 0.5,
        amount_similarity: 0.2,
        date_proximity: 0.15,
        merchant_match: 0.15
      }
      
      weights.sum { |factor, weight| (send(factor) || 0) * weight }
    end
    
    def sanitize_vector(vector)
      # Convert vector to PostgreSQL array format
      "[#{vector.join(',')}]"
    end
  end
end
```

---

## Testing Strategy

### Integration Tests
```ruby
# spec/services/ai/llm_client_spec.rb
RSpec.describe AI::LLMClient do
  let(:client) { described_class.new }
  let(:expense) { create(:expense, merchant_name: 'Walmart', amount: 45.99) }
  
  describe '#categorize' do
    context 'with successful API response' do
      before do
        stub_openai_categorization_request
      end
      
      it 'returns category with confidence' do
        result = client.categorize(expense)
        
        expect(result).to include(
          category_id: be_present,
          confidence: be_between(0, 1),
          reasoning: be_present
        )
      end
      
      it 'tracks costs' do
        expect_any_instance_of(AI::CostTracker)
          .to receive(:record)
        
        client.categorize(expense)
      end
    end
    
    context 'with API failure' do
      before do
        stub_openai_failure
      end
      
      it 'falls back to ML categorization' do
        result = client.categorize(expense)
        
        expect(result[:method]).to eq('ml_fallback')
      end
    end
    
    context 'with rate limiting' do
      it 'respects rate limits' do
        expect_any_instance_of(AI::RateLimiter)
          .to receive(:wait_if_needed)
        
        client.categorize(expense)
      end
    end
  end
  
  describe '#generate_embedding' do
    it 'returns 1536-dimension vector' do
      embedding = client.generate_embedding('test text')
      
      expect(embedding).to be_an(Array)
      expect(embedding.size).to eq(1536)
    end
    
    it 'caches embeddings' do
      text = 'test text'
      
      embedding1 = client.generate_embedding(text)
      embedding2 = client.generate_embedding(text)
      
      expect(embedding1).to eq(embedding2)
    end
  end
end
```

### Performance Tests
```ruby
# spec/benchmarks/ai_performance_spec.rb
RSpec.describe "AI Performance" do
  describe 'vector search' do
    before do
      # Create 10k expenses with embeddings
      create_expenses_with_embeddings(10_000)
    end
    
    it 'searches 10k vectors in under 100ms' do
      search = AI::SemanticSearch.new
      query_embedding = generate_random_embedding
      
      time = Benchmark.realtime do
        search.search_similar_expenses(query_embedding, limit: 10)
      end
      
      expect(time).to be < 0.1
    end
  end
  
  describe 'embedding generation' do
    it 'generates 100 embeddings in under 30 seconds' do
      expenses = create_list(:expense, 100)
      generator = AI::EmbeddingGenerator.new
      
      time = Benchmark.realtime do
        generator.batch_generate(expenses)
      end
      
      expect(time).to be < 30
    end
  end
  
  describe 'cost optimization' do
    it 'stays within budget for 1000 categorizations' do
      tracker = AI::CostTracker.new
      
      1000.times do
        simulate_categorization_cost(tracker)
      end
      
      expect(tracker.monthly_cost).to be < 10.0
    end
  end
end
```

---

## Deployment Checklist

- [ ] pgvector extension installed
- [ ] OpenAI API key configured
- [ ] Cost limits set
- [ ] Vector indexes created
- [ ] Embedding generation jobs scheduled
- [ ] Monitoring dashboards configured
- [ ] Fallback systems tested
- [ ] PII redaction verified
- [ ] Rate limiting configured
- [ ] Circuit breakers tested
# Technical Architecture - Categorization Improvement System

## System Overview

The categorization improvement system implements a three-layer architecture where each layer enhances the previous one, providing graceful degradation and optimal performance.

```
┌─────────────────────────────────────────────────────────────────┐
│                    Master Categorization System                   │
├───────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Request → Load Balancer → Rails Application                     │
│                                ↓                                  │
│                    Categorization Controller                      │
│                                ↓                                  │
│                      Intelligent Router                           │
│                         ↓      ↓      ↓                          │
│              Option 1   Option 2   Option 3                      │
│              Pattern    ML/Stats   AI/LLM                        │
│                ↓          ↓          ↓                           │
│                  Ensemble Decision                                │
│                         ↓                                         │
│                  Response + Learning                              │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

## Component Architecture

### 1. Core Components

```yaml
components:
  frontend:
    - Stimulus Controllers
    - Turbo Frames
    - Tailwind CSS
  
  backend:
    - Rails 8.0.2
    - PostgreSQL 14+
    - Redis 7+
    - Solid Queue
  
  ml_infrastructure:
    - Python 3.11
    - ONNX Runtime
    - Transformers
  
  external:
    - OpenAI API
    - Anthropic API (optional)
```

### 2. Service Layer Architecture

```ruby
# app/services/categorization/master_categorizer.rb
module Categorization
  class MasterCategorizer
    def initialize
      @router = IntelligentRouter.new
      @options = {
        quick_intelligence: QuickIntelligence.new,
        statistical_learning: StatisticalLearning.new,
        hybrid_ai: HybridAI.new
      }
    end
    
    def categorize(expense, context = {})
      # Route to appropriate option
      route = @router.determine_route(expense, context)
      
      # Execute categorization
      result = @options[route].categorize(expense, context)
      
      # Record for learning
      record_categorization(expense, result)
      
      result
    end
  end
end
```

## Database Architecture

### 1. Schema Design

```sql
-- Core Tables
expenses (
  id BIGSERIAL PRIMARY KEY,
  merchant_name VARCHAR,
  merchant_normalized VARCHAR,
  amount DECIMAL(10,2),
  category_id BIGINT REFERENCES categories,
  embedding VECTOR(384),
  ml_features JSONB,
  ml_confidence FLOAT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
)

-- Pattern Tables (Option 1)
canonical_merchants (
  id BIGSERIAL PRIMARY KEY,
  name VARCHAR UNIQUE,
  display_name VARCHAR,
  usage_count INTEGER DEFAULT 0
)

merchant_aliases (
  id BIGSERIAL PRIMARY KEY,
  raw_name VARCHAR,
  normalized_name VARCHAR,
  canonical_merchant_id BIGINT REFERENCES canonical_merchants,
  confidence FLOAT
)

category_patterns (
  id BIGSERIAL PRIMARY KEY,
  category_id BIGINT REFERENCES categories,
  pattern_type VARCHAR,
  pattern_value VARCHAR,
  success_rate FLOAT,
  weight INTEGER
)

-- ML Tables (Option 2)
ml_patterns (
  id BIGSERIAL PRIMARY KEY,
  pattern_type VARCHAR,
  pattern_value VARCHAR,
  category_id BIGINT REFERENCES categories,
  probability FLOAT,
  confidence_score FLOAT
)

ml_model_metrics (
  id BIGSERIAL PRIMARY KEY,
  model_version VARCHAR,
  accuracy FLOAT,
  evaluated_at TIMESTAMP
)

-- AI Tables (Option 3)
routing_decisions (
  id BIGSERIAL PRIMARY KEY,
  expense_id BIGINT REFERENCES expenses,
  complexity_score FLOAT,
  route_taken VARCHAR,
  confidence FLOAT,
  cost DECIMAL(10,6),
  processing_time FLOAT
)

llm_responses (
  id BIGSERIAL PRIMARY KEY,
  prompt_hash VARCHAR UNIQUE,
  response JSONB,
  model_used VARCHAR,
  cost DECIMAL(10,6),
  expires_at TIMESTAMP
)
```

### 2. Indexes Strategy

```sql
-- Performance Indexes
CREATE INDEX idx_expenses_merchant_normalized ON expenses(merchant_normalized);
CREATE INDEX idx_expenses_ml_confidence ON expenses(ml_confidence);
CREATE INDEX idx_expenses_embedding ON expenses USING ivfflat (embedding vector_l2_ops);

-- Trigram Indexes for Fuzzy Matching
CREATE INDEX idx_merchant_aliases_normalized_trgm 
  ON merchant_aliases USING gin (normalized_name gin_trgm_ops);

-- Partial Indexes for Active Patterns
CREATE INDEX idx_category_patterns_successful 
  ON category_patterns(success_rate) 
  WHERE success_rate > 0.7;

-- JSONB Indexes
CREATE INDEX idx_expenses_ml_features 
  ON expenses USING gin (ml_features jsonb_path_ops);
```

## API Architecture

### 1. RESTful Endpoints

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :expenses do
      member do
        post :categorize
        patch :correct_category
      end
      
      collection do
        post :bulk_categorize
        get :uncategorized
      end
    end
    
    resources :categories do
      member do
        get :patterns
        post :add_keyword
      end
    end
    
    namespace :ml do
      post :train
      get :metrics
      post :predict_batch
    end
    
    namespace :ai do
      get :routing_stats
      get :cost_report
      post :test_routing
    end
  end
end
```

### 2. GraphQL Schema (Optional)

```graphql
type Expense {
  id: ID!
  merchantName: String
  merchantNormalized: String
  amount: Float!
  category: Category
  confidence: Float
  suggestedCategories: [CategorySuggestion!]
}

type CategorySuggestion {
  category: Category!
  confidence: Float!
  reason: String
}

type Mutation {
  categorizeExpense(id: ID!): CategorizationResult!
  bulkCategorize(ids: [ID!]!): BulkCategorizationResult!
  correctCategory(expenseId: ID!, categoryId: ID!): Expense!
}

type Query {
  uncategorizedExpenses(limit: Int): [Expense!]!
  categorizationMetrics: Metrics!
}
```

## Caching Architecture

### 1. Multi-Layer Caching

```ruby
# config/initializers/caching.rb
Rails.application.configure do
  # Memory Cache (L1)
  config.memory_cache = ActiveSupport::Cache::MemoryStore.new(
    size: 256.megabytes,
    expires_in: 1.hour
  )
  
  # Redis Cache (L2)
  config.cache_store = :redis_cache_store, {
    url: ENV['REDIS_URL'],
    expires_in: 24.hours,
    namespace: 'categorization',
    pool_size: 5,
    pool_timeout: 5
  }
  
  # Database Cache (L3)
  config.solid_cache = {
    expires_in: 7.days,
    size_limit: 1.gigabyte
  }
end
```

### 2. Cache Key Strategy

```ruby
module CacheKeyGenerator
  def self.expense_prediction(expense)
    parts = [
      'prediction',
      expense.merchant_normalized,
      (expense.amount * 100).to_i,
      expense.transaction_date.to_s
    ]
    
    Digest::SHA256.hexdigest(parts.join(':'))
  end
  
  def self.embedding(expense)
    "embedding:#{expense.id}:#{expense.updated_at.to_i}"
  end
  
  def self.llm_response(prompt)
    "llm:#{Digest::SHA256.hexdigest(prompt)}"
  end
end
```

## Queue Architecture

### 1. Job Priority System

```ruby
# config/initializers/solid_queue.rb
SolidQueue.configure do |config|
  config.queues = {
    critical: { priority: 1, workers: 2 },
    default: { priority: 5, workers: 4 },
    ml_training: { priority: 10, workers: 1 },
    bulk_operations: { priority: 7, workers: 2 },
    analytics: { priority: 15, workers: 1 }
  }
end
```

### 2. Job Definitions

```ruby
# app/jobs/categorization_job.rb
class CategorizationJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(expense_id)
    expense = Expense.find(expense_id)
    result = MasterCategorizer.new.categorize(expense)
    
    expense.update!(
      category: result[:category],
      ml_confidence: result[:confidence],
      ml_method_used: result[:method]
    )
  end
end

# app/jobs/ml_training_job.rb
class MlTrainingJob < ApplicationJob
  queue_as :ml_training
  
  def perform
    training_data = prepare_training_data
    ML::EnsembleClassifier.new.train(training_data)
    
    MlModelMetric.create!(
      model_version: generate_version,
      accuracy: calculate_accuracy,
      evaluated_at: Time.current
    )
  end
end
```

## Security Architecture

### 1. Data Protection

```ruby
# app/services/security/data_protector.rb
module Security
  class DataProtector
    def self.encrypt_sensitive(data)
      Rails.application.message_verifier(:categorization).generate(data)
    end
    
    def self.decrypt_sensitive(encrypted)
      Rails.application.message_verifier(:categorization).verify(encrypted)
    end
    
    def self.anonymize_for_logging(expense)
      {
        id: expense.id,
        amount: expense.amount.round,
        merchant: mask_merchant(expense.merchant_name),
        category: expense.category&.name
      }
    end
    
    private
    
    def self.mask_merchant(name)
      return nil if name.blank?
      
      name.gsub(/\d{4,}/, 'XXXX')
          .gsub(/@[\w.-]+/, '@DOMAIN')
    end
  end
end
```

### 2. API Security

```ruby
# app/controllers/concerns/api_security.rb
module ApiSecurity
  extend ActiveSupport::Concern
  
  included do
    before_action :authenticate_api_token
    before_action :check_rate_limit
    before_action :validate_permissions
  end
  
  private
  
  def authenticate_api_token
    token = request.headers['X-API-Token']
    
    unless ApiToken.active.exists?(token: token)
      render json: { error: 'Invalid token' }, status: :unauthorized
    end
  end
  
  def check_rate_limit
    key = "rate_limit:#{request.ip}"
    count = Redis.current.incr(key)
    Redis.current.expire(key, 1.hour) if count == 1
    
    if count > 1000  # 1000 requests per hour
      render json: { error: 'Rate limit exceeded' }, status: :too_many_requests
    end
  end
end
```

## Monitoring Architecture

### 1. Metrics Collection

```ruby
# app/services/monitoring/metrics_collector.rb
module Monitoring
  class MetricsCollector
    include Singleton
    
    def initialize
      @client = Datadog::Statsd.new('localhost', 8125)
    end
    
    def track_categorization(expense, result, duration)
      @client.increment('categorization.count', 
        tags: ["method:#{result[:method]}", "category:#{result[:category]&.name}"]
      )
      
      @client.histogram('categorization.duration', duration,
        tags: ["method:#{result[:method]}"]
      )
      
      @client.gauge('categorization.confidence', result[:confidence],
        tags: ["method:#{result[:method]}"]
      )
      
      if result[:cost]
        @client.increment('categorization.cost', result[:cost],
          tags: ["model:#{result[:model_used]}"]
        )
      end
    end
    
    def track_error(error, context = {})
      @client.increment('categorization.errors',
        tags: ["error:#{error.class}", "context:#{context[:method]}"]
      )
      
      Sentry.capture_exception(error, extra: context)
    end
  end
end
```

### 2. Health Checks

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def show
    checks = {
      database: check_database,
      redis: check_redis,
      ml_models: check_ml_models,
      embeddings: check_embeddings,
      llm_api: check_llm_api
    }
    
    status = checks.values.all? ? :ok : :service_unavailable
    
    render json: {
      status: status,
      checks: checks,
      timestamp: Time.current
    }, status: status
  end
  
  private
  
  def check_database
    ActiveRecord::Base.connection.active?
  rescue
    false
  end
  
  def check_redis
    Redis.current.ping == "PONG"
  rescue
    false
  end
  
  def check_ml_models
    ML::EnsembleClassifier.new.healthy?
  rescue
    false
  end
end
```

## Performance Architecture

### 1. Query Optimization

```ruby
# app/models/concerns/optimized_queries.rb
module OptimizedQueries
  extend ActiveSupport::Concern
  
  included do
    scope :with_categorization_data, -> {
      includes(:category, :email_account)
        .select('expenses.*, 
                 categories.name as category_name,
                 email_accounts.bank_name as bank_name')
    }
    
    scope :for_bulk_categorization, -> {
      uncategorized
        .includes(:email_account)
        .where('created_at > ?', 6.months.ago)
        .order(amount: :desc)
    }
  end
  
  class_methods do
    def batch_categorize(batch_size: 100)
      uncategorized.find_in_batches(batch_size: batch_size) do |batch|
        CategoriBatchJob.perform_later(batch.map(&:id))
      end
    end
  end
end
```

### 2. Connection Pooling

```yaml
# config/database.yml
production:
  adapter: postgresql
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 25 } %>
  timeout: 5000
  reaping_frequency: 10
  
  # Read replica for heavy queries
  replica:
    adapter: postgresql
    host: <%= ENV['DATABASE_REPLICA_HOST'] %>
    pool: 15
    replica: true
```

## Deployment Architecture

### 1. Container Configuration

```dockerfile
# Dockerfile
FROM ruby:3.3.0-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
  postgresql-client \
  python3-pip \
  && rm -rf /var/lib/apt/lists/*

# Install Python packages for ML
RUN pip3 install onnxruntime transformers torch

# Install Ruby gems
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4

# Copy application
COPY . .

# Precompile assets and embeddings
RUN rails assets:precompile
RUN rails ml:download_models

EXPOSE 3000
CMD ["rails", "server", "-b", "0.0.0.0"]
```

### 2. Kubernetes Deployment

```yaml
# k8s/deployment.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: categorization-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: categorization
  template:
    metadata:
      labels:
        app: categorization
    spec:
      containers:
      - name: rails
        image: categorization:latest
        ports:
        - containerPort: 3000
        env:
        - name: RAILS_ENV
          value: production
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: redis-secret
              key: url
        - name: OPENAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: openai-secret
              key: key
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
```

## Scaling Architecture

### 1. Horizontal Scaling

```ruby
# config/puma.rb
workers ENV.fetch("WEB_CONCURRENCY") { 2 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

preload_app!

on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  
  # Reconnect Redis
  Redis.current.disconnect!
  Redis.current = Redis.new(url: ENV['REDIS_URL'])
  
  # Load ML models
  ML::ModelLoader.load_all
end
```

### 2. Auto-scaling Rules

```yaml
# k8s/hpa.yml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: categorization-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: categorization-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  - type: Pods
    pods:
      metric:
        name: categorization_queue_depth
      target:
        type: AverageValue
        averageValue: "30"
```

## Disaster Recovery

### 1. Backup Strategy

```ruby
# lib/tasks/backup.rake
namespace :backup do
  desc "Backup critical categorization data"
  task categorization: :environment do
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    
    # Backup patterns
    backup_patterns(timestamp)
    
    # Backup ML models
    backup_ml_models(timestamp)
    
    # Backup embeddings
    backup_embeddings(timestamp)
    
    # Upload to S3
    upload_to_s3(timestamp)
  end
  
  private
  
  def backup_patterns(timestamp)
    File.open("backups/patterns_#{timestamp}.json", 'w') do |f|
      patterns = CategoryPattern.successful.to_json
      f.write(patterns)
    end
  end
  
  def backup_ml_models(timestamp)
    ML::ModelExporter.export_all("backups/models_#{timestamp}")
  end
end
```

### 2. Recovery Procedures

```ruby
# lib/tasks/recovery.rake
namespace :recovery do
  desc "Restore categorization system"
  task restore: :environment do
    # Restore patterns
    restore_patterns
    
    # Restore ML models
    restore_ml_models
    
    # Regenerate embeddings
    regenerate_embeddings
    
    # Warm caches
    warm_caches
  end
end
```

## Development Environment

### 1. Docker Compose Setup

```yaml
# docker-compose.yml
version: '3.8'

services:
  db:
    image: postgres:14
    environment:
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    command: >
      postgres
      -c shared_preload_libraries='pg_stat_statements,pgvector'
      -c pg_stat_statements.track=all
  
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
  
  app:
    build: .
    command: bundle exec rails server -b 0.0.0.0
    volumes:
      - .:/app
    ports:
      - "3000:3000"
    depends_on:
      - db
      - redis
    environment:
      DATABASE_URL: postgresql://postgres:password@db/categorization_dev
      REDIS_URL: redis://redis:6379/0
  
  worker:
    build: .
    command: bundle exec solid_queue:start
    volumes:
      - .:/app
    depends_on:
      - db
      - redis
    environment:
      DATABASE_URL: postgresql://postgres:password@db/categorization_dev
      REDIS_URL: redis://redis:6379/0

volumes:
  postgres_data:
```

### 2. Development Tools

```ruby
# Gemfile (development group)
group :development do
  gem 'annotate'           # Model annotations
  gem 'bullet'            # N+1 query detection
  gem 'rack-mini-profiler' # Performance profiling
  gem 'memory_profiler'    # Memory profiling
  gem 'derailed_benchmarks' # Performance benchmarking
  gem 'prosopite'         # N+1 detection
end
```

## Testing Architecture

### 1. Test Environment Setup

```ruby
# spec/support/test_helpers.rb
module TestHelpers
  def mock_ml_prediction(category, confidence = 0.85)
    allow_any_instance_of(ML::EnsembleClassifier)
      .to receive(:predict)
      .and_return({
        category: category,
        confidence: confidence,
        method: 'test'
      })
  end
  
  def mock_llm_response(response)
    allow_any_instance_of(AI::LLMLayer)
      .to receive(:categorize)
      .and_return(response)
  end
  
  def disable_external_apis
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end
```

### 2. Performance Testing

```ruby
# spec/performance/categorization_performance_spec.rb
require 'rails_helper'
require 'benchmark'

RSpec.describe 'Categorization Performance' do
  it 'categorizes 1000 expenses in under 10 seconds' do
    expenses = create_list(:expense, 1000)
    
    time = Benchmark.realtime do
      expenses.each do |expense|
        MasterCategorizer.new.categorize(expense)
      end
    end
    
    expect(time).to be < 10
  end
  
  it 'maintains memory usage under 500MB' do
    initial = GetProcessMem.new.mb
    
    1000.times do
      expense = create(:expense)
      MasterCategorizer.new.categorize(expense)
    end
    
    final = GetProcessMem.new.mb
    expect(final - initial).to be < 500
  end
end
```

## Conclusion

This technical architecture provides a comprehensive, scalable, and maintainable system for the three-layer categorization improvement. The architecture ensures:

1. **Modularity**: Each component is independent and replaceable
2. **Scalability**: Horizontal scaling through containerization
3. **Reliability**: Multiple fallback mechanisms and caching layers
4. **Performance**: Optimized queries and efficient processing
5. **Security**: Data protection and API security
6. **Observability**: Comprehensive monitoring and logging
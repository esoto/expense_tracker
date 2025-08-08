# Option 2: ML Foundation Tasks - Statistical Learning

## Phase 1: ML Infrastructure Setup (Week 1)

### Task ML-1.1: Database Schema for ML Models
**Priority**: Critical  
**Estimated Hours**: 4  
**Dependencies**: Option 1 completion  

#### Description
Create database tables for ML model storage, training data, and predictions.

#### Acceptance Criteria
- [ ] Migration creates `ml_models` table with versioning
- [ ] Migration creates `ml_training_data` table
- [ ] Migration creates `ml_predictions` table
- [ ] Migration creates `ml_feature_configs` table
- [ ] Support for model serialization up to 50MB
- [ ] Indexes for performance optimization
- [ ] Test data seeding capability

#### Technical Implementation
```ruby
# db/migrate/[timestamp]_create_ml_infrastructure.rb
class CreateMlInfrastructure < ActiveRecord::Migration[8.0]
  def change
    create_table :ml_models do |t|
      t.string :name, null: false
      t.string :model_type, null: false # naive_bayes, decision_tree, etc
      t.integer :version, null: false
      t.binary :model_data, limit: 50.megabytes
      t.binary :vectorizer_data, limit: 10.megabytes
      t.json :feature_config
      t.json :training_params
      t.json :performance_metrics
      t.float :accuracy
      t.float :precision
      t.float :recall  
      t.float :f1_score
      t.integer :training_samples_count
      t.boolean :active, default: false
      t.datetime :trained_at
      t.timestamps
      
      t.index [:model_type, :version], unique: true
      t.index [:model_type, :active]
      t.index :trained_at
    end
    
    create_table :ml_training_data do |t|
      t.references :expense, null: false, foreign_key: true
      t.references :ml_model, foreign_key: true
      t.json :features
      t.references :category, null: false, foreign_key: true
      t.boolean :is_test_set, default: false
      t.float :weight, default: 1.0
      t.timestamps
      
      t.index [:ml_model_id, :is_test_set]
      t.index :created_at
    end
    
    create_table :ml_predictions do |t|
      t.references :expense, null: false, foreign_key: true
      t.references :ml_model, null: false, foreign_key: true
      t.references :predicted_category, foreign_key: { to_table: :categories }
      t.float :confidence
      t.json :probability_distribution
      t.json :features_used
      t.string :prediction_method
      t.float :processing_time_ms
      t.timestamps
      
      t.index [:expense_id, :ml_model_id]
      t.index [:predicted_category_id, :confidence]
      t.index :created_at
    end
  end
end
```

#### Model Implementation
```ruby
# app/models/ml_model.rb
class MlModel < ApplicationRecord
  has_many :ml_training_data
  has_many :ml_predictions
  
  validates :name, presence: true
  validates :model_type, inclusion: { 
    in: %w[naive_bayes decision_tree random_forest ensemble] 
  }
  validates :version, uniqueness: { scope: :model_type }
  validates :accuracy, numericality: { in: 0..1 }, allow_nil: true
  
  scope :active, -> { where(active: true) }
  scope :for_type, ->(type) { where(model_type: type) }
  scope :latest, -> { order(version: :desc).first }
  
  def self.current(model_type = 'naive_bayes')
    for_type(model_type).active.latest
  end
  
  def activate!
    transaction do
      self.class.for_type(model_type).update_all(active: false)
      update!(active: true)
    end
  end
  
  def deserialize_model
    @model ||= Marshal.load(Base64.decode64(model_data))
  rescue => e
    Rails.logger.error "Failed to deserialize model: #{e.message}"
    nil
  end
  
  def serialize_model=(model_object)
    self.model_data = Base64.encode64(Marshal.dump(model_object))
  end
end
```

---

### Task ML-1.2: Feature Extraction Service
**Priority**: Critical  
**Estimated Hours**: 8  
**Dependencies**: Task ML-1.1  

#### Description
Build comprehensive feature extraction system for expense data.

#### Acceptance Criteria
- [ ] Extracts 50+ features from expenses
- [ ] Text features with TF-IDF vectorization
- [ ] Numerical features with normalization
- [ ] Temporal features with cyclical encoding
- [ ] Categorical features with one-hot encoding
- [ ] Feature caching for performance
- [ ] Configurable feature selection
- [ ] Handle missing data gracefully

#### Technical Implementation
```ruby
# app/services/ml/feature_extractor.rb
module ML
  class FeatureExtractor
    STOP_WORDS_ES = %w[el la de en un una por para con sin sobre]
    STOP_WORDS_EN = %w[the a an in on at for with without about]
    
    def initialize(config = {})
      @config = default_config.merge(config)
      @tokenizer = Tokenizer.new
      @stemmer = Lingua::Stemmer.new
    end
    
    def extract(expense)
      features = {}
      
      # Text features
      features.merge!(extract_text_features(expense))
      
      # Numerical features
      features.merge!(extract_numerical_features(expense))
      
      # Temporal features
      features.merge!(extract_temporal_features(expense))
      
      # Categorical features
      features.merge!(extract_categorical_features(expense))
      
      # Historical features
      features.merge!(extract_historical_features(expense))
      
      # Normalize if configured
      normalize_features(features) if @config[:normalize]
      
      features
    end
    
    def extract_batch(expenses)
      expenses.map { |e| extract(e) }
    end
    
    private
    
    def extract_text_features(expense)
      text = combine_text_fields(expense)
      tokens = tokenize_and_clean(text)
      
      features = {}
      
      # Unigrams
      tokens.each do |token|
        features["word_#{token}"] = 1
      end
      
      # Bigrams
      tokens.each_cons(2) do |bigram|
        features["bigram_#{bigram.join('_')}"] = 1
      end
      
      # Character-level features
      features['text_length'] = text.length
      features['word_count'] = tokens.size
      features['avg_word_length'] = tokens.map(&:length).sum.to_f / tokens.size
      features['has_numbers'] = text =~ /\d/ ? 1 : 0
      features['has_special_chars'] = text =~ /[^a-zA-Z0-9\s]/ ? 1 : 0
      
      # Language detection
      features['lang_es_score'] = calculate_language_score(text, :es)
      features['lang_en_score'] = calculate_language_score(text, :en)
      
      features
    end
    
    def extract_numerical_features(expense)
      amount = expense.amount.to_f
      
      {
        'amount' => amount,
        'amount_log' => Math.log10(amount + 1),
        'amount_sqrt' => Math.sqrt(amount),
        'amount_bucket_small' => amount < 20 ? 1 : 0,
        'amount_bucket_medium' => amount.between?(20, 100) ? 1 : 0,
        'amount_bucket_large' => amount.between?(100, 500) ? 1 : 0,
        'amount_bucket_xlarge' => amount > 500 ? 1 : 0,
        'amount_cents' => (amount % 1 * 100).round,
        'is_round_amount' => (amount % 10).zero? ? 1 : 0,
        'is_recurring_amount' => check_recurring_amount(expense) ? 1 : 0
      }
    end
    
    def extract_temporal_features(expense)
      date = expense.transaction_date
      
      {
        # Cyclical encoding for periodic features
        'day_of_week_sin' => Math.sin(2 * Math::PI * date.wday / 7),
        'day_of_week_cos' => Math.cos(2 * Math::PI * date.wday / 7),
        'day_of_month_sin' => Math.sin(2 * Math::PI * date.day / 31),
        'day_of_month_cos' => Math.cos(2 * Math::PI * date.day / 31),
        'month_sin' => Math.sin(2 * Math::PI * date.month / 12),
        'month_cos' => Math.cos(2 * Math::PI * date.month / 12),
        
        # Binary features
        'is_weekend' => [0, 6].include?(date.wday) ? 1 : 0,
        'is_month_start' => date.day <= 5 ? 1 : 0,
        'is_month_end' => date.day >= 26 ? 1 : 0,
        'is_business_day' => !weekend?(date) ? 1 : 0,
        
        # Time-based if available
        'hour_of_day' => extract_hour(expense),
        'is_morning' => morning_transaction?(expense) ? 1 : 0,
        'is_evening' => evening_transaction?(expense) ? 1 : 0
      }
    end
    
    def extract_categorical_features(expense)
      features = {}
      
      # Bank features
      if expense.email_account
        bank = expense.email_account.bank_name
        features["bank_#{normalize_category(bank)}"] = 1
      end
      
      # Currency features
      features["currency_#{expense.currency || 'CRC'}"] = 1
      
      # Merchant type detection
      merchant = expense.merchant_name.to_s.downcase
      features['merchant_has_number'] = merchant =~ /\d/ ? 1 : 0
      features['merchant_all_caps'] = merchant == merchant.upcase ? 1 : 0
      features['merchant_online'] = online_merchant?(merchant) ? 1 : 0
      
      features
    end
    
    def extract_historical_features(expense)
      user_expenses = expense.user.expenses
      merchant_history = user_expenses.where(merchant_name: expense.merchant_name)
      
      {
        'merchant_frequency' => merchant_history.count,
        'merchant_avg_amount' => merchant_history.average(:amount).to_f,
        'days_since_last_merchant' => days_since_last(merchant_history),
        'user_total_expenses' => user_expenses.count,
        'user_avg_daily_expenses' => calculate_daily_average(user_expenses),
        'similar_amount_frequency' => count_similar_amounts(expense)
      }
    end
    
    def normalize_features(features)
      # Min-max normalization for numerical features
      numerical_features = features.select { |k, v| v.is_a?(Numeric) }
      
      return features if numerical_features.empty?
      
      min = numerical_features.values.min
      max = numerical_features.values.max
      range = max - min
      
      return features if range.zero?
      
      numerical_features.each do |key, value|
        features[key] = (value - min) / range
      end
      
      features
    end
  end
end
```

---

### Task ML-1.3: Naive Bayes Classifier Implementation
**Priority**: Critical  
**Estimated Hours**: 10  
**Dependencies**: Task ML-1.2  

#### Description
Implement Multinomial Naive Bayes classifier with Ruby.

#### Acceptance Criteria
- [ ] Training with Laplace smoothing
- [ ] Incremental learning support
- [ ] Probability calculation for all classes
- [ ] Cross-validation implementation
- [ ] Model serialization/deserialization
- [ ] Performance: < 100ms for prediction
- [ ] Memory efficient for 100k+ features

#### Technical Implementation
```ruby
# app/services/ml/naive_bayes_classifier.rb
module ML
  class NaiveBayesClassifier
    attr_reader :class_priors, :feature_probs, :vocabulary, :metrics
    
    def initialize(alpha: 1.0)
      @alpha = alpha # Laplace smoothing parameter
      @class_priors = {}
      @feature_probs = {}
      @vocabulary = Set.new
      @class_counts = Hash.new(0)
      @feature_counts = Hash.new { |h, k| h[k] = Hash.new(0) }
      @metrics = {}
    end
    
    def train(training_data)
      reset_model
      
      # Count occurrences
      training_data.each do |sample|
        features = sample[:features]
        label = sample[:label]
        
        @class_counts[label] += 1
        
        features.each do |feature, value|
          @vocabulary.add(feature)
          @feature_counts[label][feature] += value
        end
      end
      
      # Calculate priors
      total_samples = training_data.size.to_f
      @class_priors = @class_counts.transform_values { |count| 
        Math.log(count / total_samples)
      }
      
      # Calculate feature probabilities with smoothing
      calculate_feature_probabilities
      
      # Evaluate on training set
      evaluate_model(training_data)
      
      self
    end
    
    def predict(features, return_probabilities: false)
      scores = {}
      
      @class_priors.each do |class_label, prior|
        score = prior
        
        features.each do |feature, value|
          if @vocabulary.include?(feature)
            prob = @feature_probs[class_label][feature] || default_probability
            score += Math.log(prob) * value
          end
        end
        
        scores[class_label] = score
      end
      
      if return_probabilities
        # Convert log probabilities to probabilities
        probabilities = normalize_scores(scores)
        build_probability_result(probabilities)
      else
        # Return class with highest score
        scores.max_by { |_, score| score }[0]
      end
    end
    
    def partial_fit(new_samples)
      # Incremental learning
      new_samples.each do |sample|
        features = sample[:features]
        label = sample[:label]
        
        @class_counts[label] += 1
        
        features.each do |feature, value|
          @vocabulary.add(feature)
          @feature_counts[label][feature] += value
        end
      end
      
      # Recalculate probabilities
      recalculate_model
    end
    
    def cross_validate(data, folds: 5)
      fold_size = data.size / folds
      cv_scores = []
      
      folds.times do |i|
        test_start = i * fold_size
        test_end = (i + 1) * fold_size
        
        test_data = data[test_start...test_end]
        train_data = data[0...test_start] + data[test_end..-1]
        
        # Train on fold
        train(train_data)
        
        # Evaluate on test fold
        correct = test_data.count { |sample|
          predict(sample[:features]) == sample[:label]
        }
        
        accuracy = correct.to_f / test_data.size
        cv_scores << accuracy
      end
      
      {
        mean_accuracy: cv_scores.sum / cv_scores.size,
        std_deviation: calculate_std_dev(cv_scores),
        fold_scores: cv_scores
      }
    end
    
    def serialize
      {
        alpha: @alpha,
        class_priors: @class_priors,
        feature_probs: @feature_probs,
        vocabulary: @vocabulary.to_a,
        class_counts: @class_counts,
        metrics: @metrics
      }
    end
    
    def self.deserialize(data)
      classifier = new(alpha: data[:alpha])
      classifier.instance_variable_set(:@class_priors, data[:class_priors])
      classifier.instance_variable_set(:@feature_probs, data[:feature_probs])
      classifier.instance_variable_set(:@vocabulary, data[:vocabulary].to_set)
      classifier.instance_variable_set(:@class_counts, data[:class_counts])
      classifier.instance_variable_set(:@metrics, data[:metrics])
      classifier
    end
    
    private
    
    def calculate_feature_probabilities
      vocab_size = @vocabulary.size.to_f
      
      @feature_probs = {}
      
      @class_counts.each do |class_label, class_count|
        @feature_probs[class_label] = {}
        
        # Total feature count for this class
        total_features = @feature_counts[class_label].values.sum.to_f
        
        @vocabulary.each do |feature|
          count = @feature_counts[class_label][feature] || 0
          # Laplace smoothing
          prob = (count + @alpha) / (total_features + @alpha * vocab_size)
          @feature_probs[class_label][feature] = prob
        end
      end
    end
    
    def normalize_scores(scores)
      # Convert log scores to probabilities
      max_score = scores.values.max
      exp_scores = scores.transform_values { |s| Math.exp(s - max_score) }
      sum = exp_scores.values.sum
      
      exp_scores.transform_values { |s| s / sum }
    end
  end
end
```

---

### Task ML-1.4: Training Pipeline Service
**Priority**: Critical  
**Estimated Hours**: 6  
**Dependencies**: Tasks ML-1.2, ML-1.3  

#### Description
Create service to manage model training lifecycle.

#### Acceptance Criteria
- [ ] Data preparation with stratified sampling
- [ ] Train/test split (80/20)
- [ ] Feature selection and engineering
- [ ] Model training with progress tracking
- [ ] Performance evaluation metrics
- [ ] Model versioning and storage
- [ ] Automated hyperparameter tuning
- [ ] Training job queuing

#### Technical Implementation
```ruby
# app/services/ml/training_pipeline.rb
module ML
  class TrainingPipeline
    include Sidekiq::Worker
    
    def initialize(model_type: 'naive_bayes')
      @model_type = model_type
      @feature_extractor = FeatureExtractor.new
      @metrics_calculator = MetricsCalculator.new
    end
    
    def execute
      Rails.logger.info "Starting ML training pipeline for #{@model_type}"
      
      # Step 1: Data preparation
      training_data, test_data = prepare_data
      
      # Step 2: Feature extraction
      X_train, y_train = extract_features(training_data)
      X_test, y_test = extract_features(test_data)
      
      # Step 3: Train model
      model = train_model(X_train, y_train)
      
      # Step 4: Evaluate
      metrics = evaluate_model(model, X_test, y_test)
      
      # Step 5: Save if better than current
      save_model_if_better(model, metrics)
      
      metrics
    end
    
    private
    
    def prepare_data
      # Get labeled expenses
      expenses = Expense
        .where.not(category_id: nil)
        .where('created_at > ?', 6.months.ago)
        .includes(:category, :email_account)
      
      # Remove outliers
      expenses = remove_outliers(expenses)
      
      # Balance dataset
      expenses = balance_dataset(expenses)
      
      # Stratified split
      stratified_split(expenses, test_size: 0.2)
    end
    
    def extract_features(expenses)
      features = []
      labels = []
      
      expenses.each do |expense|
        feature_vector = @feature_extractor.extract(expense)
        features << feature_vector
        labels << expense.category_id
      end
      
      [features, labels]
    end
    
    def train_model(features, labels)
      model = case @model_type
      when 'naive_bayes'
        NaiveBayesClassifier.new(alpha: find_best_alpha)
      when 'decision_tree'
        DecisionTreeClassifier.new(max_depth: 10)
      else
        raise "Unknown model type: #{@model_type}"
      end
      
      # Convert to training format
      training_data = features.zip(labels).map do |f, l|
        { features: f, label: l }
      end
      
      model.train(training_data)
    end
    
    def evaluate_model(model, X_test, y_test)
      predictions = X_test.map { |features| model.predict(features) }
      
      @metrics_calculator.calculate(
        y_true: y_test,
        y_pred: predictions,
        labels: Category.pluck(:id)
      )
    end
    
    def save_model_if_better(model, metrics)
      current_model = MlModel.current(@model_type)
      
      if !current_model || metrics[:f1_score] > current_model.f1_score
        Rails.logger.info "New model performs better, saving..."
        
        new_model = MlModel.create!(
          name: "#{@model_type}_v#{next_version}",
          model_type: @model_type,
          version: next_version,
          accuracy: metrics[:accuracy],
          precision: metrics[:precision],
          recall: metrics[:recall],
          f1_score: metrics[:f1_score],
          performance_metrics: metrics,
          trained_at: Time.current
        )
        
        new_model.serialize_model = model
        new_model.save!
        
        # Activate new model
        new_model.activate!
      end
    end
    
    def find_best_alpha
      # Grid search for best smoothing parameter
      alphas = [0.001, 0.01, 0.1, 0.5, 1.0, 2.0]
      best_alpha = 1.0
      best_score = 0
      
      alphas.each do |alpha|
        model = NaiveBayesClassifier.new(alpha: alpha)
        cv_results = model.cross_validate(prepare_cv_data)
        
        if cv_results[:mean_accuracy] > best_score
          best_score = cv_results[:mean_accuracy]
          best_alpha = alpha
        end
      end
      
      Rails.logger.info "Best alpha: #{best_alpha} (score: #{best_score})"
      best_alpha
    end
  end
end
```

---

## Testing Strategy

### Unit Tests
```ruby
# spec/services/ml/naive_bayes_classifier_spec.rb
RSpec.describe ML::NaiveBayesClassifier do
  let(:classifier) { described_class.new(alpha: 1.0) }
  let(:training_data) { build_training_data }
  
  describe '#train' do
    it 'learns from training data' do
      classifier.train(training_data)
      
      expect(classifier.class_priors).not_to be_empty
      expect(classifier.vocabulary.size).to be > 0
    end
    
    it 'achieves minimum accuracy' do
      classifier.train(training_data)
      
      correct = training_data.count { |sample|
        classifier.predict(sample[:features]) == sample[:label]
      }
      
      accuracy = correct.to_f / training_data.size
      expect(accuracy).to be > 0.7
    end
  end
  
  describe '#predict' do
    before { classifier.train(training_data) }
    
    it 'returns most likely class' do
      features = { 'word_grocery' => 1, 'amount_bucket_medium' => 1 }
      prediction = classifier.predict(features)
      
      expect(prediction).to be_a(Integer)
    end
    
    it 'returns probability distribution when requested' do
      features = { 'word_grocery' => 1 }
      result = classifier.predict(features, return_probabilities: true)
      
      expect(result[:probabilities]).to be_a(Hash)
      expect(result[:probabilities].values.sum).to be_within(0.01).of(1.0)
    end
  end
  
  describe '#cross_validate' do
    it 'performs k-fold cross validation' do
      results = classifier.cross_validate(training_data, folds: 5)
      
      expect(results[:fold_scores].size).to eq(5)
      expect(results[:mean_accuracy]).to be_between(0, 1)
    end
  end
end
```

### Performance Tests
```ruby
# spec/benchmarks/ml_performance_spec.rb
RSpec.describe "ML Performance" do
  let(:classifier) { ML::NaiveBayesClassifier.new }
  let(:feature_extractor) { ML::FeatureExtractor.new }
  
  it 'trains on 10k samples in under 30 seconds' do
    training_data = generate_training_samples(10_000)
    
    time = Benchmark.realtime do
      classifier.train(training_data)
    end
    
    expect(time).to be < 30
  end
  
  it 'predicts 1000 expenses per second' do
    classifier.train(generate_training_samples(1000))
    test_features = generate_test_features(1000)
    
    time = Benchmark.realtime do
      test_features.each { |f| classifier.predict(f) }
    end
    
    expect(time).to be < 1
  end
  
  it 'maintains memory usage under 500MB' do
    initial = GetProcessMem.new.mb
    
    classifier.train(generate_training_samples(10_000))
    1000.times { classifier.predict(generate_test_features.sample) }
    
    final = GetProcessMem.new.mb
    expect(final - initial).to be < 500
  end
end
```

---

## Deployment Checklist

- [ ] ML model tables migrated
- [ ] Initial model trained
- [ ] Performance benchmarks met
- [ ] API endpoints tested
- [ ] Monitoring configured
- [ ] Rollback plan documented
- [ ] Team trained on ML operations
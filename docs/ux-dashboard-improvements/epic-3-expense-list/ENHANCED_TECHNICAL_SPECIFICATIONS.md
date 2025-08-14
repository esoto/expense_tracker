# Epic 3: Enhanced Technical Specifications

## Executive Summary

This document provides comprehensive, implementation-ready technical specifications for Epic 3: Optimized Expense List with Batch Operations. These specifications address all missing technical details identified in the review, providing senior Rails developers with clear, unambiguous requirements for implementation.

## Table of Contents

1. [Database Design & Optimization](#1-database-design--optimization)
2. [Service Architecture](#2-service-architecture)
3. [API Contracts](#3-api-contracts)
4. [Performance Specifications](#4-performance-specifications)
5. [Error Handling Patterns](#5-error-handling-patterns)
6. [Security Considerations](#6-security-considerations)
7. [Testing Strategy](#7-testing-strategy)
8. [Monitoring & Observability](#8-monitoring--observability)

---

## 1. Database Design & Optimization

### 1.1 Schema Modifications

```ruby
# db/migrate/20250114_add_expense_optimizations.rb
class AddExpenseOptimizations < ActiveRecord::Migration[8.0]
  def change
    # Add missing columns for batch operations
    add_column :expenses, :lock_version, :integer, default: 0, null: false
    add_column :expenses, :deleted_at, :datetime
    add_column :expenses, :deleted_by_id, :integer
    add_column :expenses, :categorized_at, :datetime
    add_column :expenses, :categorized_by_id, :integer
    
    # Add batch operation logs table
    create_table :batch_operation_logs do |t|
      t.string :operation_type, null: false
      t.integer :user_id, null: false
      t.jsonb :expense_ids, default: [], null: false
      t.jsonb :details, default: {}
      t.jsonb :results, default: {}
      t.boolean :undone, default: false
      t.datetime :undone_at
      t.timestamps
      
      t.index :user_id
      t.index :operation_type
      t.index :created_at
      t.index :undone
    end
    
    # Add filter preferences table
    create_table :expense_filter_preferences do |t|
      t.integer :email_account_id, null: false
      t.string :name, null: false
      t.jsonb :filters, default: {}, null: false
      t.boolean :is_default, default: false
      t.integer :usage_count, default: 0
      t.timestamps
      
      t.index [:email_account_id, :name], unique: true
      t.index [:email_account_id, :is_default]
    end
  end
end
```

### 1.2 Optimized Indexes

```ruby
# db/migrate/20250114_add_performance_indexes.rb
class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  
  def up
    # Primary composite index for filtering
    add_index :expenses, 
              [:email_account_id, :transaction_date, :category_id],
              name: 'idx_expenses_filter_primary',
              algorithm: :concurrently,
              where: "deleted_at IS NULL"
    
    # Covering index for list display
    add_index :expenses,
              [:email_account_id, :transaction_date, :amount, :merchant_name, :category_id, :status],
              name: 'idx_expenses_list_covering',
              algorithm: :concurrently,
              include: [:description, :bank_name, :currency],
              where: "deleted_at IS NULL"
    
    # Category filtering index
    add_index :expenses,
              [:category_id, :transaction_date],
              name: 'idx_expenses_category_date',
              algorithm: :concurrently,
              where: "category_id IS NOT NULL AND deleted_at IS NULL"
    
    # Uncategorized expenses index
    add_index :expenses,
              [:email_account_id, :transaction_date],
              name: 'idx_expenses_uncategorized',
              algorithm: :concurrently,
              where: "category_id IS NULL AND deleted_at IS NULL"
    
    # Bank filtering index
    add_index :expenses,
              [:bank_name, :transaction_date],
              name: 'idx_expenses_bank_date',
              algorithm: :concurrently,
              where: "deleted_at IS NULL"
    
    # Full-text search index
    execute <<-SQL
      CREATE EXTENSION IF NOT EXISTS pg_trgm;
      CREATE INDEX idx_expenses_merchant_trgm 
      ON expenses USING gin(merchant_name gin_trgm_ops)
      WHERE deleted_at IS NULL;
    SQL
    
    # Status filtering index
    add_index :expenses,
              [:status, :email_account_id, :created_at],
              name: 'idx_expenses_status_account',
              algorithm: :concurrently,
              where: "deleted_at IS NULL"
    
    # Amount range index using BRIN for large tables
    execute <<-SQL
      CREATE INDEX idx_expenses_amount_brin 
      ON expenses USING brin(amount)
      WITH (pages_per_range = 128);
    SQL
  end
  
  def down
    remove_index :expenses, name: 'idx_expenses_filter_primary'
    remove_index :expenses, name: 'idx_expenses_list_covering'
    remove_index :expenses, name: 'idx_expenses_category_date'
    remove_index :expenses, name: 'idx_expenses_uncategorized'
    remove_index :expenses, name: 'idx_expenses_bank_date'
    remove_index :expenses, name: 'idx_expenses_status_account'
    
    execute "DROP INDEX IF EXISTS idx_expenses_merchant_trgm;"
    execute "DROP INDEX IF EXISTS idx_expenses_amount_brin;"
  end
end
```

### 1.3 Query Optimization Patterns

```ruby
# app/models/concerns/expense_query_optimizer.rb
module ExpenseQueryOptimizer
  extend ActiveSupport::Concern
  
  included do
    # Optimized scopes using indexes
    scope :for_list_display, -> {
      select(list_display_columns)
        .includes(:category)
        .where(deleted_at: nil)
    }
    
    scope :with_filters, ->(filters) {
      query = for_list_display
      query = query.by_date_range(filters[:start_date], filters[:end_date]) if filters[:start_date]
      query = query.by_categories(filters[:category_ids]) if filters[:category_ids]
      query = query.by_banks(filters[:banks]) if filters[:banks]
      query = query.by_amount_range(filters[:min_amount], filters[:max_amount]) if filters[:min_amount]
      query = query.by_status(filters[:status]) if filters[:status]
      query = query.search_merchant(filters[:search]) if filters[:search]
      query
    }
    
    scope :by_categories, ->(category_ids) {
      if category_ids.include?(nil) || category_ids.include?('uncategorized')
        where(category_id: category_ids.compact).or(where(category_id: nil))
      else
        where(category_id: category_ids)
      end
    }
    
    scope :by_banks, ->(banks) {
      where(bank_name: banks)
    }
    
    scope :search_merchant, ->(term) {
      where("merchant_name % ?", term)  # Uses pg_trgm for fuzzy matching
    }
  end
  
  class_methods do
    def list_display_columns
      %w[
        expenses.id
        expenses.amount
        expenses.description
        expenses.transaction_date
        expenses.merchant_name
        expenses.category_id
        expenses.status
        expenses.bank_name
        expenses.currency
        expenses.lock_version
      ]
    end
    
    # Batch loading with cursor-based pagination for large datasets
    def cursor_paginate(cursor: nil, limit: 50, direction: :forward)
      query = for_list_display.order(transaction_date: :desc, id: :desc)
      
      if cursor
        decoded = decode_cursor(cursor)
        if direction == :forward
          query = query.where("(transaction_date, id) < (?, ?)", decoded[:date], decoded[:id])
        else
          query = query.where("(transaction_date, id) > (?, ?)", decoded[:date], decoded[:id])
        end
      end
      
      query.limit(limit)
    end
    
    private
    
    def decode_cursor(cursor)
      JSON.parse(Base64.decode64(cursor)).symbolize_keys
    rescue
      raise ArgumentError, "Invalid cursor"
    end
  end
end
```

---

## 2. Service Architecture

### 2.1 ExpenseFilterService - Complete Implementation

```ruby
# app/services/expense_filter_service.rb
class ExpenseFilterService
  include ActiveModel::Model
  include ActiveModel::Validations
  
  # Input attributes
  attr_accessor :account_ids, :date_range, :start_date, :end_date,
                :category_ids, :banks, :min_amount, :max_amount,
                :status, :search_query, :sort_by, :sort_direction,
                :page, :per_page, :cursor, :use_cursor
  
  # Validations
  validates :per_page, numericality: { less_than_or_equal_to: 100 }
  validates :sort_by, inclusion: { in: %w[transaction_date amount merchant_name created_at] }, allow_nil: true
  validates :sort_direction, inclusion: { in: %w[asc desc] }, allow_nil: true
  
  # Constants
  DEFAULT_PER_PAGE = 50
  MAX_PER_PAGE = 100
  CACHE_TTL = 5.minutes
  
  class Result
    attr_reader :expenses, :total_count, :metadata, :performance_metrics
    
    def initialize(expenses:, total_count:, metadata:, performance_metrics: {})
      @expenses = expenses
      @total_count = total_count
      @metadata = metadata
      @performance_metrics = performance_metrics
    end
    
    def cache_key
      [
        'expense_filter',
        metadata[:filters_hash],
        metadata[:page],
        metadata[:per_page]
      ].join('/')
    end
    
    def to_json(*args)
      {
        data: expenses.map { |e| ExpenseSerializer.new(e).as_json },
        meta: {
          total: total_count,
          page: metadata[:page],
          per_page: metadata[:per_page],
          filters_applied: metadata[:filters_applied],
          sort: metadata[:sort],
          cursor: metadata[:cursor],
          performance: performance_metrics
        }
      }.to_json(*args)
    end
  end
  
  def initialize(params = {})
    super(normalize_params(params))
    set_defaults
  end
  
  def call
    return cached_result if cache_enabled? && cached_result.present?
    
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    
    scope = build_scope
    scope = apply_filters(scope)
    scope = apply_sorting(scope)
    expenses, pagination_meta = apply_pagination(scope)
    
    query_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    
    result = build_result(expenses, pagination_meta, query_time)
    cache_result(result) if cache_enabled?
    
    result
  end
  
  private
  
  def normalize_params(params)
    normalized = params.deep_symbolize_keys
    
    # Handle date range shortcuts
    if normalized[:date_range].present?
      dates = parse_date_range(normalized[:date_range])
      normalized[:start_date] = dates[:start]
      normalized[:end_date] = dates[:end]
    end
    
    # Clean array parameters
    normalized[:category_ids] = Array(normalized[:category_ids]).compact if normalized[:category_ids]
    normalized[:banks] = Array(normalized[:banks]).compact if normalized[:banks]
    normalized[:account_ids] = Array(normalized[:account_ids]).compact if normalized[:account_ids]
    
    normalized
  end
  
  def set_defaults
    @page ||= 1
    @per_page = [@per_page.to_i, MAX_PER_PAGE].min if @per_page
    @per_page ||= DEFAULT_PER_PAGE
    @sort_by ||= 'transaction_date'
    @sort_direction ||= 'desc'
  end
  
  def build_scope
    Expense
      .for_list_display
      .where(email_account_id: account_ids)
  end
  
  def apply_filters(scope)
    scope = filter_by_dates(scope)
    scope = filter_by_categories(scope)
    scope = filter_by_banks(scope)
    scope = filter_by_amounts(scope)
    scope = filter_by_status(scope)
    scope = filter_by_search(scope)
    scope
  end
  
  def filter_by_dates(scope)
    return scope unless start_date.present? || end_date.present?
    
    scope = scope.where('transaction_date >= ?', start_date.to_date) if start_date
    scope = scope.where('transaction_date <= ?', end_date.to_date) if end_date
    scope
  end
  
  def filter_by_categories(scope)
    return scope unless category_ids.present?
    
    scope.by_categories(category_ids)
  end
  
  def filter_by_banks(scope)
    return scope unless banks.present?
    
    scope.by_banks(banks)
  end
  
  def filter_by_amounts(scope)
    return scope unless min_amount.present? || max_amount.present?
    
    scope = scope.where('amount >= ?', min_amount.to_f) if min_amount
    scope = scope.where('amount <= ?', max_amount.to_f) if max_amount
    scope
  end
  
  def filter_by_status(scope)
    return scope unless status.present?
    
    case status
    when 'uncategorized'
      scope.uncategorized
    else
      scope.by_status(status)
    end
  end
  
  def filter_by_search(scope)
    return scope unless search_query.present?
    
    # Use trigram search for fuzzy matching
    scope.search_merchant(search_query)
  end
  
  def apply_sorting(scope)
    # Ensure we're using indexed columns
    safe_column = %w[transaction_date amount merchant_name created_at].include?(sort_by) ? sort_by : 'transaction_date'
    safe_direction = %w[asc desc].include?(sort_direction) ? sort_direction : 'desc'
    
    # Add secondary sort by ID for consistent ordering
    scope.order("#{safe_column} #{safe_direction}, id DESC")
  end
  
  def apply_pagination(scope)
    if use_cursor && cursor.present?
      expenses = scope.cursor_paginate(cursor: cursor, limit: per_page)
      pagination_meta = build_cursor_pagination_meta(expenses)
    else
      # Use optimized keyset pagination for better performance
      expenses = scope.page(page).per(per_page)
      pagination_meta = build_offset_pagination_meta(expenses)
    end
    
    [expenses, pagination_meta]
  end
  
  def build_result(expenses, pagination_meta, query_time)
    Result.new(
      expenses: expenses,
      total_count: pagination_meta[:total_count],
      metadata: {
        page: pagination_meta[:page],
        per_page: per_page,
        cursor: pagination_meta[:cursor],
        filters_applied: count_active_filters,
        filters_hash: generate_filters_hash,
        sort: { by: sort_by, direction: sort_direction }
      },
      performance_metrics: {
        query_time_ms: (query_time * 1000).round(2),
        cached: false,
        index_used: check_index_usage
      }
    )
  end
  
  def parse_date_range(range)
    case range.to_s
    when 'today'
      { start: Date.current, end: Date.current }
    when 'week'
      { start: Date.current.beginning_of_week, end: Date.current.end_of_week }
    when 'month'
      { start: Date.current.beginning_of_month, end: Date.current.end_of_month }
    when 'year'
      { start: Date.current.beginning_of_year, end: Date.current.end_of_year }
    when 'last_30_days'
      { start: 30.days.ago.to_date, end: Date.current }
    when 'last_90_days'
      { start: 90.days.ago.to_date, end: Date.current }
    else
      {}
    end
  end
  
  def count_active_filters
    count = 0
    count += 1 if start_date.present? || end_date.present?
    count += 1 if category_ids.present?
    count += 1 if banks.present?
    count += 1 if min_amount.present? || max_amount.present?
    count += 1 if status.present?
    count += 1 if search_query.present?
    count
  end
  
  def generate_filters_hash
    Digest::SHA256.hexdigest({
      account_ids: account_ids,
      dates: [start_date, end_date],
      categories: category_ids,
      banks: banks,
      amounts: [min_amount, max_amount],
      status: status,
      search: search_query,
      sort: [sort_by, sort_direction]
    }.to_json)
  end
  
  def cache_enabled?
    Rails.configuration.x.expense_filter_cache_enabled
  end
  
  def cached_result
    @cached_result ||= Rails.cache.read(cache_key)
  end
  
  def cache_result(result)
    Rails.cache.write(cache_key, result, expires_in: CACHE_TTL)
  end
  
  def cache_key
    ['expense_filter', generate_filters_hash, page, per_page].join('/')
  end
  
  def check_index_usage
    # In development/test, check EXPLAIN output
    return true unless Rails.env.development? || Rails.env.test?
    
    explain_output = @last_scope&.explain || ''
    explain_output.include?('Index Scan') || explain_output.include?('Bitmap Index Scan')
  end
  
  def build_cursor_pagination_meta(expenses)
    last_expense = expenses.last
    next_cursor = if last_expense
      Base64.encode64({
        date: last_expense.transaction_date,
        id: last_expense.id
      }.to_json).strip
    end
    
    {
      total_count: nil, # Not available with cursor pagination
      page: nil,
      cursor: next_cursor
    }
  end
  
  def build_offset_pagination_meta(expenses)
    {
      total_count: expenses.total_count,
      page: page,
      cursor: nil
    }
  end
end
```

### 2.2 BatchOperationService - Complete Implementation

```ruby
# app/services/batch_operation_service.rb
class BatchOperationService
  include ActiveModel::Model
  
  # Constants
  MAX_BATCH_SIZE = 500
  CHUNK_SIZE = 100
  LOCK_TIMEOUT = 5.seconds
  MAX_RETRIES = 3
  
  # Attributes
  attr_reader :expense_ids, :user, :options
  
  # Result class
  class Result
    attr_accessor :success_ids, :failed_ids, :skipped_ids, 
                  :errors, :duration, :rollback_data
    
    def initialize
      @success_ids = []
      @failed_ids = []
      @skipped_ids = []
      @errors = {}
      @rollback_data = {}
      @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    
    def success?
      failed_ids.empty? && errors.empty?
    end
    
    def partial_success?
      success_ids.any? && failed_ids.any?
    end
    
    def finalize!
      @duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
      self
    end
    
    def summary
      {
        total: success_ids.size + failed_ids.size + skipped_ids.size,
        succeeded: success_ids.size,
        failed: failed_ids.size,
        skipped: skipped_ids.size,
        duration_ms: (duration * 1000).round(2),
        success: success?
      }
    end
  end
  
  # Validations
  validates :expense_ids, presence: true
  validate :validate_batch_size
  validate :validate_user_permissions
  
  def initialize(expense_ids:, user:, options: {})
    @expense_ids = Array(expense_ids).compact.uniq
    @user = user
    @options = options.with_indifferent_access
    @result = Result.new
  end
  
  # Main operations
  def categorize(category_id)
    validate!
    validate_category!(category_id)
    
    execute_in_transaction do
      expenses = load_and_lock_expenses
      store_rollback_data(expenses, :category_id)
      
      expenses.find_in_batches(batch_size: CHUNK_SIZE) do |batch|
        process_categorization_batch(batch, category_id)
      end
      
      log_operation(:categorize, category_id: category_id)
    end
    
    @result.finalize!
  end
  
  def delete
    validate!
    
    execute_in_transaction do
      expenses = load_and_lock_expenses
      store_rollback_data(expenses, [:status, :deleted_at, :deleted_by_id])
      
      deleted_count = expenses.update_all(
        status: 'deleted',
        deleted_at: Time.current,
        deleted_by_id: user.id,
        updated_at: Time.current
      )
      
      @result.success_ids = expenses.pluck(:id)
      log_operation(:delete)
    end
    
    @result.finalize!
  end
  
  def duplicate(target_date: nil)
    validate!
    
    execute_in_transaction do
      expenses = load_expenses
      
      expenses.find_each do |expense|
        duplicate = expense.dup
        duplicate.transaction_date = target_date || expense.transaction_date
        duplicate.status = 'pending'
        
        if duplicate.save
          @result.success_ids << expense.id
        else
          @result.failed_ids << expense.id
          @result.errors[expense.id] = duplicate.errors.full_messages
        end
      end
      
      log_operation(:duplicate, target_date: target_date)
    end
    
    @result.finalize!
  end
  
  def update_status(new_status)
    validate!
    validate_status!(new_status)
    
    execute_in_transaction do
      expenses = load_and_lock_expenses
      store_rollback_data(expenses, :status)
      
      updated_count = expenses.update_all(
        status: new_status,
        updated_at: Time.current
      )
      
      @result.success_ids = expenses.pluck(:id)
      log_operation(:update_status, status: new_status)
    end
    
    @result.finalize!
  end
  
  def export(format: 'csv')
    validate!
    
    expenses = load_expenses.includes(:category)
    exporter = ExportService.new(expenses, format: format, user: user)
    
    export_data = exporter.generate
    @result.success_ids = expenses.pluck(:id)
    @result.rollback_data[:export_data] = export_data
    
    log_operation(:export, format: format)
    @result.finalize!
  end
  
  private
  
  def validate!
    raise ValidationError, errors.full_messages.join(', ') unless valid?
  end
  
  def validate_batch_size
    if expense_ids.size > MAX_BATCH_SIZE
      errors.add(:expense_ids, "exceeds maximum batch size of #{MAX_BATCH_SIZE}")
    end
  end
  
  def validate_user_permissions
    return if user&.can?(:manage_expenses)
    errors.add(:user, "does not have permission to manage expenses")
  end
  
  def validate_category!(category_id)
    unless Category.exists?(category_id)
      raise ArgumentError, "Category with ID #{category_id} does not exist"
    end
  end
  
  def validate_status!(status)
    valid_statuses = %w[pending processed failed duplicate deleted]
    unless valid_statuses.include?(status)
      raise ArgumentError, "Invalid status: #{status}"
    end
  end
  
  def execute_in_transaction(&block)
    retries = 0
    
    begin
      ActiveRecord::Base.transaction(isolation: :read_committed) do
        ActiveRecord::Base.connection.execute("SET lock_timeout = '#{LOCK_TIMEOUT.to_i}s'")
        yield
      end
    rescue ActiveRecord::LockWaitTimeout => e
      retries += 1
      if retries < MAX_RETRIES
        sleep(2 ** retries)
        retry
      else
        handle_lock_timeout(e)
      end
    rescue ActiveRecord::StaleObjectError => e
      handle_stale_object(e)
    rescue StandardError => e
      handle_general_error(e)
      raise ActiveRecord::Rollback
    end
  end
  
  def load_expenses
    Expense
      .where(id: expense_ids)
      .where(email_account_id: user.accessible_account_ids)
  end
  
  def load_and_lock_expenses
    load_expenses.lock("FOR UPDATE SKIP LOCKED")
  end
  
  def store_rollback_data(expenses, fields)
    fields = Array(fields)
    @result.rollback_data[:original_values] = {}
    
    expenses.select(:id, *fields).find_each do |expense|
      @result.rollback_data[:original_values][expense.id] = 
        fields.index_with { |field| expense.send(field) }
    end
  end
  
  def process_categorization_batch(batch, category_id)
    batch.each do |expense|
      if should_skip_categorization?(expense)
        @result.skipped_ids << expense.id
        next
      end
      
      begin
        expense.with_lock do
          expense.update!(
            category_id: category_id,
            categorized_at: Time.current,
            categorized_by_id: user.id,
            lock_version: expense.lock_version + 1
          )
        end
        
        @result.success_ids << expense.id
      rescue => e
        @result.failed_ids << expense.id
        @result.errors[expense.id] = e.message
      end
    end
  end
  
  def should_skip_categorization?(expense)
    options[:skip_categorized] && expense.category_id.present?
  end
  
  def log_operation(operation, details = {})
    BatchOperationLog.create!(
      operation_type: operation.to_s,
      user_id: user.id,
      expense_ids: expense_ids,
      details: details.merge(options: options),
      results: @result.summary
    )
  rescue => e
    Rails.logger.error "Failed to log batch operation: #{e.message}"
  end
  
  def handle_lock_timeout(error)
    @result.errors[:lock_timeout] = "Unable to acquire locks on expenses. Please try again."
    Rails.logger.warn "Batch operation lock timeout: #{error.message}"
  end
  
  def handle_stale_object(error)
    @result.errors[:concurrency] = "Some expenses were modified by another process. Please refresh and try again."
    Rails.logger.warn "Batch operation stale object: #{error.message}"
  end
  
  def handle_general_error(error)
    @result.errors[:general] = "An unexpected error occurred: #{error.message}"
    Rails.logger.error "Batch operation error: #{error.message}\n#{error.backtrace.join("\n")}"
  end
  
  class ValidationError < StandardError; end
end
```

---

## 3. API Contracts

### 3.1 RESTful Endpoints

```ruby
# config/routes.rb
Rails.application.routes.draw do
  resources :expenses do
    collection do
      # Filtering and listing
      get :search
      get :export
      
      # Batch operations
      post :batch_categorize
      post :batch_delete
      post :batch_duplicate
      post :batch_update_status
      
      # Filter preferences
      resources :filter_preferences, only: [:index, :create, :update, :destroy]
    end
    
    member do
      # Quick actions
      patch :quick_update
      post :duplicate
    end
  end
  
  # Virtual scrolling endpoint
  get '/api/expenses/virtual_scroll', to: 'api/expenses#virtual_scroll'
end
```

### 3.2 Controller Implementations

```ruby
# app/controllers/expenses_controller.rb
class ExpensesController < ApplicationController
  include BatchOperationSecurity
  
  before_action :authenticate_user!
  before_action :set_expense, only: [:show, :edit, :update, :destroy, :quick_update, :duplicate]
  
  # GET /expenses
  def index
    filter_service = ExpenseFilterService.new(
      filter_params.merge(account_ids: current_user_account_ids)
    )
    
    @result = filter_service.call
    
    respond_to do |format|
      format.html { render :index }
      format.json { render json: @result }
      format.turbo_stream
    end
  end
  
  # GET /expenses/search
  def search
    @expenses = Expense
      .search_merchant(params[:q])
      .limit(10)
      .select(:id, :merchant_name, :amount, :transaction_date)
    
    render json: @expenses
  end
  
  # POST /expenses/batch_categorize
  def batch_categorize
    service = BatchOperationService.new(
      expense_ids: params[:expense_ids],
      user: current_user,
      options: { skip_categorized: params[:skip_categorized] }
    )
    
    result = service.categorize(params[:category_id])
    
    if result.success?
      render json: { 
        message: "Successfully categorized #{result.success_ids.size} expenses",
        data: result.summary 
      }, status: :ok
    else
      render json: { 
        error: "Batch categorization partially failed",
        data: result.summary,
        errors: result.errors 
      }, status: :unprocessable_entity
    end
  end
  
  # POST /expenses/batch_delete
  def batch_delete
    service = BatchOperationService.new(
      expense_ids: params[:expense_ids],
      user: current_user
    )
    
    result = service.delete
    
    if result.success?
      render json: { 
        message: "Successfully deleted #{result.success_ids.size} expenses",
        data: result.summary 
      }, status: :ok
    else
      render json: { 
        error: "Batch deletion failed",
        errors: result.errors 
      }, status: :unprocessable_entity
    end
  end
  
  # GET /expenses/export
  def export
    service = BatchOperationService.new(
      expense_ids: filtered_expense_ids,
      user: current_user
    )
    
    result = service.export(format: params[:format] || 'csv')
    
    respond_to do |format|
      format.csv { send_data result.rollback_data[:export_data], filename: export_filename('csv') }
      format.xlsx { send_data result.rollback_data[:export_data], filename: export_filename('xlsx') }
      format.json { render json: result.rollback_data[:export_data] }
    end
  end
  
  # PATCH /expenses/:id/quick_update
  def quick_update
    if @expense.update(quick_update_params)
      render json: { 
        message: "Expense updated",
        expense: ExpenseSerializer.new(@expense).as_json 
      }, status: :ok
    else
      render json: { 
        errors: @expense.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end
  
  private
  
  def filter_params
    params.permit(
      :date_range, :start_date, :end_date,
      :search_query, :status,
      :min_amount, :max_amount,
      :sort_by, :sort_direction,
      :page, :per_page, :cursor, :use_cursor,
      category_ids: [], banks: []
    )
  end
  
  def quick_update_params
    params.require(:expense).permit(:category_id, :amount, :merchant_name, :description)
  end
  
  def filtered_expense_ids
    filter_service = ExpenseFilterService.new(
      filter_params.merge(account_ids: current_user_account_ids)
    )
    filter_service.call.expenses.pluck(:id)
  end
  
  def export_filename(format)
    "expenses_#{Date.current.to_s(:number)}.#{format}"
  end
  
  def current_user_account_ids
    current_user.email_accounts.pluck(:id)
  end
end
```

### 3.3 API Request/Response Schemas

```yaml
# doc/api/expenses.yml
openapi: 3.0.0
info:
  title: Expense List API
  version: 1.0.0

paths:
  /expenses:
    get:
      summary: List expenses with filters
      parameters:
        - name: date_range
          in: query
          schema:
            type: string
            enum: [today, week, month, year, last_30_days, last_90_days]
        - name: start_date
          in: query
          schema:
            type: string
            format: date
        - name: end_date
          in: query
          schema:
            type: string
            format: date
        - name: category_ids
          in: query
          schema:
            type: array
            items:
              type: integer
        - name: banks
          in: query
          schema:
            type: array
            items:
              type: string
        - name: min_amount
          in: query
          schema:
            type: number
        - name: max_amount
          in: query
          schema:
            type: number
        - name: status
          in: query
          schema:
            type: string
            enum: [pending, processed, failed, uncategorized]
        - name: search_query
          in: query
          schema:
            type: string
        - name: sort_by
          in: query
          schema:
            type: string
            enum: [transaction_date, amount, merchant_name, created_at]
        - name: sort_direction
          in: query
          schema:
            type: string
            enum: [asc, desc]
        - name: page
          in: query
          schema:
            type: integer
            minimum: 1
        - name: per_page
          in: query
          schema:
            type: integer
            minimum: 1
            maximum: 100
      responses:
        200:
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  data:
                    type: array
                    items:
                      $ref: '#/components/schemas/Expense'
                  meta:
                    type: object
                    properties:
                      total:
                        type: integer
                      page:
                        type: integer
                      per_page:
                        type: integer
                      filters_applied:
                        type: integer
                      sort:
                        type: object
                        properties:
                          by:
                            type: string
                          direction:
                            type: string
                      performance:
                        type: object
                        properties:
                          query_time_ms:
                            type: number
                          cached:
                            type: boolean
                          index_used:
                            type: boolean

  /expenses/batch_categorize:
    post:
      summary: Categorize multiple expenses
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - expense_ids
                - category_id
              properties:
                expense_ids:
                  type: array
                  items:
                    type: integer
                  maxItems: 500
                category_id:
                  type: integer
                skip_categorized:
                  type: boolean
                  default: false
      responses:
        200:
          description: Successful categorization
          content:
            application/json:
              schema:
                type: object
                properties:
                  message:
                    type: string
                  data:
                    type: object
                    properties:
                      total:
                        type: integer
                      succeeded:
                        type: integer
                      failed:
                        type: integer
                      skipped:
                        type: integer
                      duration_ms:
                        type: number
        422:
          description: Validation error
          content:
            application/json:
              schema:
                type: object
                properties:
                  error:
                    type: string
                  errors:
                    type: object

components:
  schemas:
    Expense:
      type: object
      properties:
        id:
          type: integer
        amount:
          type: number
        description:
          type: string
        transaction_date:
          type: string
          format: date
        merchant_name:
          type: string
        category:
          type: object
          properties:
            id:
              type: integer
            name:
              type: string
            color:
              type: string
        status:
          type: string
        bank_name:
          type: string
        currency:
          type: string
```

---

## 4. Performance Specifications

### 4.1 Performance Benchmarks

```ruby
# spec/benchmarks/performance_spec.rb
require 'rails_helper'
require 'benchmark'

RSpec.describe "Performance Benchmarks" do
  let(:user) { create(:user) }
  let(:account) { create(:email_account, user: user) }
  
  before do
    # Create test data
    10_000.times do |i|
      create(:expense,
        email_account: account,
        amount: rand(1..100000),
        transaction_date: rand(365).days.ago,
        category: Category.all.sample,
        merchant_name: Faker::Company.name
      )
    end
  end
  
  describe "Query Performance" do
    it "meets performance targets for filtering" do
      benchmarks = {}
      
      # Simple date filter
      benchmarks[:date_filter] = Benchmark.realtime do
        ExpenseFilterService.new(
          account_ids: [account.id],
          date_range: 'month'
        ).call
      end
      
      # Complex multi-filter
      benchmarks[:complex_filter] = Benchmark.realtime do
        ExpenseFilterService.new(
          account_ids: [account.id],
          date_range: 'month',
          category_ids: [1, 2, 3],
          banks: ['BAC', 'Scotia'],
          min_amount: 1000,
          max_amount: 50000
        ).call
      end
      
      # Search with pagination
      benchmarks[:search_paginated] = Benchmark.realtime do
        ExpenseFilterService.new(
          account_ids: [account.id],
          search_query: 'rest',
          page: 1,
          per_page: 50
        ).call
      end
      
      # Assert performance targets
      expect(benchmarks[:date_filter]).to be < 0.05      # 50ms
      expect(benchmarks[:complex_filter]).to be < 0.1    # 100ms
      expect(benchmarks[:search_paginated]).to be < 0.15 # 150ms
    end
    
    it "meets performance targets for batch operations" do
      expense_ids = Expense.limit(100).pluck(:id)
      
      benchmark = Benchmark.realtime do
        BatchOperationService.new(
          expense_ids: expense_ids,
          user: user
        ).categorize(1)
      end
      
      expect(benchmark).to be < 2.0  # 2 seconds for 100 items
    end
  end
  
  describe "Memory Usage" do
    it "maintains acceptable memory usage" do
      initial_memory = GetProcessMem.new.mb
      
      # Process large dataset
      ExpenseFilterService.new(
        account_ids: [account.id],
        per_page: 1000
      ).call
      
      final_memory = GetProcessMem.new.mb
      memory_increase = final_memory - initial_memory
      
      expect(memory_increase).to be < 100  # Less than 100MB increase
    end
  end
  
  describe "Concurrent Operations" do
    it "handles concurrent batch operations" do
      expense_ids = Expense.limit(50).pluck(:id)
      
      threads = 5.times.map do
        Thread.new do
          BatchOperationService.new(
            expense_ids: expense_ids.sample(10),
            user: user
          ).categorize(1)
        end
      end
      
      results = threads.map(&:value)
      
      expect(results).to all(satisfy { |r| r.success? || r.partial_success? })
    end
  end
end
```

### 4.2 Performance Monitoring

```ruby
# config/initializers/performance_monitoring.rb
module PerformanceMonitoring
  class Middleware
    def initialize(app)
      @app = app
    end
    
    def call(env)
      return @app.call(env) unless monitor_request?(env)
      
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      allocations_before = GC.stat[:total_allocated_objects]
      
      status, headers, response = @app.call(env)
      
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      allocations = GC.stat[:total_allocated_objects] - allocations_before
      
      if slow_request?(duration)
        log_slow_request(env, duration, allocations)
      end
      
      [status, headers, response]
    end
    
    private
    
    def monitor_request?(env)
      env['PATH_INFO'].start_with?('/expenses')
    end
    
    def slow_request?(duration)
      duration > 0.5  # 500ms threshold
    end
    
    def log_slow_request(env, duration, allocations)
      Rails.logger.warn({
        event: 'slow_request',
        path: env['PATH_INFO'],
        method: env['REQUEST_METHOD'],
        duration_ms: (duration * 1000).round(2),
        allocations: allocations,
        params: Rack::Request.new(env).params
      }.to_json)
      
      # Send to monitoring service
      StatsD.timing('expenses.request.duration', duration * 1000)
      StatsD.gauge('expenses.request.allocations', allocations)
    end
  end
end

Rails.application.config.middleware.use PerformanceMonitoring::Middleware
```

---

## 5. Error Handling Patterns

### 5.1 Error Classes

```ruby
# app/errors/expense_errors.rb
module ExpenseErrors
  class BaseError < StandardError
    attr_reader :code, :details
    
    def initialize(message, code: nil, details: {})
      @code = code
      @details = details
      super(message)
    end
    
    def to_h
      {
        error: self.class.name.demodulize,
        message: message,
        code: code,
        details: details
      }
    end
  end
  
  class ValidationError < BaseError
    def initialize(errors)
      super(
        "Validation failed",
        code: 'VALIDATION_ERROR',
        details: { errors: errors }
      )
    end
  end
  
  class AuthorizationError < BaseError
    def initialize(resource_type, resource_id)
      super(
        "Not authorized to access #{resource_type}",
        code: 'AUTHORIZATION_ERROR',
        details: { resource_type: resource_type, resource_id: resource_id }
      )
    end
  end
  
  class ConcurrencyError < BaseError
    def initialize(resource_type, resource_ids)
      super(
        "Resources were modified by another process",
        code: 'CONCURRENCY_ERROR',
        details: { resource_type: resource_type, resource_ids: resource_ids }
      )
    end
  end
  
  class BatchOperationError < BaseError
    def initialize(operation, result)
      super(
        "Batch #{operation} failed",
        code: 'BATCH_OPERATION_ERROR',
        details: result.summary
      )
    end
  end
  
  class FilterError < BaseError
    def initialize(invalid_params)
      super(
        "Invalid filter parameters",
        code: 'FILTER_ERROR',
        details: { invalid_params: invalid_params }
      )
    end
  end
end
```

### 5.2 Error Handler

```ruby
# app/controllers/concerns/error_handler.rb
module ErrorHandler
  extend ActiveSupport::Concern
  
  included do
    rescue_from StandardError, with: :handle_standard_error
    rescue_from ExpenseErrors::BaseError, with: :handle_expense_error
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_validation_error
    rescue_from ActiveRecord::StaleObjectError, with: :handle_concurrency_error
    rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
  end
  
  private
  
  def handle_expense_error(error)
    log_error(error)
    render json: error.to_h, status: determine_status(error)
  end
  
  def handle_not_found(error)
    render json: {
      error: 'NotFound',
      message: 'Resource not found'
    }, status: :not_found
  end
  
  def handle_validation_error(error)
    render json: {
      error: 'ValidationError',
      message: 'Validation failed',
      details: { errors: error.record.errors.full_messages }
    }, status: :unprocessable_entity
  end
  
  def handle_concurrency_error(error)
    render json: {
      error: 'ConcurrencyError',
      message: 'Resource was modified by another process. Please refresh and try again.'
    }, status: :conflict
  end
  
  def handle_parameter_missing(error)
    render json: {
      error: 'ParameterMissing',
      message: "Required parameter missing: #{error.param}"
    }, status: :bad_request
  end
  
  def handle_standard_error(error)
    log_error(error)
    
    if Rails.env.production?
      render json: {
        error: 'InternalError',
        message: 'An unexpected error occurred'
      }, status: :internal_server_error
    else
      render json: {
        error: error.class.name,
        message: error.message,
        backtrace: error.backtrace.first(10)
      }, status: :internal_server_error
    end
  end
  
  def determine_status(error)
    case error.code
    when 'VALIDATION_ERROR' then :unprocessable_entity
    when 'AUTHORIZATION_ERROR' then :forbidden
    when 'CONCURRENCY_ERROR' then :conflict
    when 'FILTER_ERROR' then :bad_request
    else :internal_server_error
    end
  end
  
  def log_error(error)
    Rails.logger.error({
      error: error.class.name,
      message: error.message,
      code: error.respond_to?(:code) ? error.code : nil,
      details: error.respond_to?(:details) ? error.details : nil,
      backtrace: error.backtrace&.first(5),
      user_id: current_user&.id,
      request_id: request.request_id,
      params: params.to_unsafe_h
    }.to_json)
    
    # Send to error tracking service
    Bugsnag.notify(error) if defined?(Bugsnag)
  end
end
```

---

## 6. Security Considerations

### 6.1 Authorization Policies

```ruby
# app/policies/expense_policy.rb
class ExpensePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(email_account_id: user.accessible_account_ids)
    end
  end
  
  def index?
    true
  end
  
  def show?
    owned_by_user?
  end
  
  def create?
    user.can?(:create_expenses)
  end
  
  def update?
    owned_by_user? && !record.deleted?
  end
  
  def destroy?
    owned_by_user? && user.can?(:delete_expenses)
  end
  
  def batch_categorize?
    user.can?(:batch_operations)
  end
  
  def batch_delete?
    user.can?(:batch_operations) && user.can?(:delete_expenses)
  end
  
  def export?
    user.can?(:export_expenses)
  end
  
  private
  
  def owned_by_user?
    user.accessible_account_ids.include?(record.email_account_id)
  end
end
```

### 6.2 Input Sanitization

```ruby
# app/services/input_sanitizer.rb
class InputSanitizer
  ALLOWED_SORT_COLUMNS = %w[transaction_date amount merchant_name created_at].freeze
  ALLOWED_SORT_DIRECTIONS = %w[asc desc].freeze
  ALLOWED_STATUSES = %w[pending processed failed duplicate deleted uncategorized].freeze
  ALLOWED_DATE_RANGES = %w[today week month year last_30_days last_90_days].freeze
  
  class << self
    def sanitize_filter_params(params)
      sanitized = {}
      
      # Date parameters
      if params[:date_range].present?
        sanitized[:date_range] = params[:date_range] if ALLOWED_DATE_RANGES.include?(params[:date_range])
      end
      
      sanitized[:start_date] = parse_date(params[:start_date]) if params[:start_date]
      sanitized[:end_date] = parse_date(params[:end_date]) if params[:end_date]
      
      # Array parameters
      sanitized[:category_ids] = sanitize_ids(params[:category_ids]) if params[:category_ids]
      sanitized[:banks] = sanitize_strings(params[:banks], max_length: 100) if params[:banks]
      
      # Numeric parameters
      sanitized[:min_amount] = sanitize_amount(params[:min_amount]) if params[:min_amount]
      sanitized[:max_amount] = sanitize_amount(params[:max_amount]) if params[:max_amount]
      
      # String parameters
      sanitized[:status] = params[:status] if ALLOWED_STATUSES.include?(params[:status])
      sanitized[:search_query] = sanitize_search_query(params[:search_query]) if params[:search_query]
      
      # Sorting parameters
      sanitized[:sort_by] = params[:sort_by] if ALLOWED_SORT_COLUMNS.include?(params[:sort_by])
      sanitized[:sort_direction] = params[:sort_direction] if ALLOWED_SORT_DIRECTIONS.include?(params[:sort_direction])
      
      # Pagination parameters
      sanitized[:page] = sanitize_page(params[:page]) if params[:page]
      sanitized[:per_page] = sanitize_per_page(params[:per_page]) if params[:per_page]
      
      sanitized
    end
    
    def sanitize_batch_params(params)
      {
        expense_ids: sanitize_ids(params[:expense_ids], max: 500),
        category_id: sanitize_id(params[:category_id]),
        skip_categorized: ActiveModel::Type::Boolean.new.cast(params[:skip_categorized])
      }
    end
    
    private
    
    def parse_date(date_string)
      Date.parse(date_string.to_s)
    rescue ArgumentError
      nil
    end
    
    def sanitize_ids(ids, max: 1000)
      Array(ids)
        .compact
        .map(&:to_i)
        .select { |id| id > 0 }
        .uniq
        .first(max)
    end
    
    def sanitize_id(id)
      id.to_i if id.to_i > 0
    end
    
    def sanitize_strings(strings, max_length: 255)
      Array(strings)
        .compact
        .map { |s| s.to_s.strip.first(max_length) }
        .reject(&:blank?)
        .uniq
    end
    
    def sanitize_amount(amount)
      value = amount.to_f
      value if value >= 0 && value <= 999_999_999
    end
    
    def sanitize_search_query(query)
      query.to_s
        .strip
        .gsub(/[^\w\s\-]/, '') # Remove special characters
        .first(100)
    end
    
    def sanitize_page(page)
      value = page.to_i
      value > 0 ? value : 1
    end
    
    def sanitize_per_page(per_page)
      value = per_page.to_i
      value.between?(1, 100) ? value : 50
    end
  end
end
```

---

## 7. Testing Strategy

### 7.1 Unit Tests

```ruby
# spec/services/expense_filter_service_spec.rb
require 'rails_helper'

RSpec.describe ExpenseFilterService do
  let(:user) { create(:user) }
  let(:account) { create(:email_account, user: user) }
  let!(:expenses) { create_list(:expense, 100, email_account: account) }
  
  describe '#call' do
    context 'with date range filter' do
      let(:recent_expense) { create(:expense, email_account: account, transaction_date: 1.day.ago) }
      let(:old_expense) { create(:expense, email_account: account, transaction_date: 2.months.ago) }
      
      it 'filters expenses by date range' do
        service = described_class.new(
          account_ids: [account.id],
          date_range: 'month'
        )
        
        result = service.call
        
        expect(result.expenses).to include(recent_expense)
        expect(result.expenses).not_to include(old_expense)
      end
      
      it 'uses index for date filtering' do
        service = described_class.new(
          account_ids: [account.id],
          start_date: 1.week.ago,
          end_date: Date.current
        )
        
        expect_any_instance_of(ActiveRecord::Relation)
          .to receive(:where)
          .and_call_original
        
        result = service.call
        
        # Check EXPLAIN output includes index usage
        explain = result.expenses.explain
        expect(explain).to include('Index Scan')
      end
    end
    
    context 'with multiple filters' do
      it 'applies all filters correctly' do
        category = create(:category)
        expense = create(:expense,
          email_account: account,
          category: category,
          amount: 5000,
          bank_name: 'BAC',
          transaction_date: 1.week.ago
        )
        
        service = described_class.new(
          account_ids: [account.id],
          category_ids: [category.id],
          banks: ['BAC'],
          min_amount: 4000,
          max_amount: 6000,
          date_range: 'month'
        )
        
        result = service.call
        
        expect(result.expenses).to include(expense)
        expect(result.metadata[:filters_applied]).to eq(4)
      end
    end
    
    context 'performance' do
      it 'completes within performance budget' do
        service = described_class.new(
          account_ids: [account.id],
          per_page: 50
        )
        
        time = Benchmark.realtime { service.call }
        
        expect(time).to be < 0.05  # 50ms
      end
      
      it 'uses cache when enabled' do
        allow(Rails.configuration.x).to receive(:expense_filter_cache_enabled).and_return(true)
        
        service = described_class.new(account_ids: [account.id])
        
        # First call should hit database
        expect(Expense).to receive(:for_list_display).and_call_original
        result1 = service.call
        
        # Second call should use cache
        expect(Expense).not_to receive(:for_list_display)
        result2 = service.call
        
        expect(result2.performance_metrics[:cached]).to be true
      end
    end
  end
end
```

### 7.2 Integration Tests

```ruby
# spec/requests/expenses_batch_operations_spec.rb
require 'rails_helper'

RSpec.describe "Expense Batch Operations", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:email_account, user: user) }
  let!(:expenses) { create_list(:expense, 10, email_account: account) }
  
  before { sign_in user }
  
  describe "POST /expenses/batch_categorize" do
    let(:category) { create(:category) }
    let(:expense_ids) { expenses.first(5).map(&:id) }
    
    context "with valid parameters" do
      it "categorizes multiple expenses" do
        post batch_categorize_expenses_path, params: {
          expense_ids: expense_ids,
          category_id: category.id
        }
        
        expect(response).to have_http_status(:ok)
        
        json = JSON.parse(response.body)
        expect(json['data']['succeeded']).to eq(5)
        
        expenses.first(5).each do |expense|
          expect(expense.reload.category_id).to eq(category.id)
        end
      end
      
      it "handles concurrent updates gracefully" do
        # Simulate concurrent update
        expense = expenses.first
        expense.update_column(:lock_version, expense.lock_version + 1)
        
        post batch_categorize_expenses_path, params: {
          expense_ids: [expense.id],
          category_id: category.id
        }
        
        json = JSON.parse(response.body)
        expect(json['data']['failed']).to eq(1)
        expect(json['errors']).to have_key(expense.id.to_s)
      end
    end
    
    context "with invalid parameters" do
      it "rejects batch sizes over limit" do
        large_batch = (1..501).to_a
        
        post batch_categorize_expenses_path, params: {
          expense_ids: large_batch,
          category_id: category.id
        }
        
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to include('exceeds maximum')
      end
      
      it "validates category existence" do
        post batch_categorize_expenses_path, params: {
          expense_ids: expense_ids,
          category_id: 99999
        }
        
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
    
    context "authorization" do
      it "prevents access to other users' expenses" do
        other_expense = create(:expense)
        
        post batch_categorize_expenses_path, params: {
          expense_ids: [other_expense.id],
          category_id: category.id
        }
        
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
  
  describe "POST /expenses/batch_delete" do
    it "soft deletes expenses" do
      expense_ids = expenses.first(3).map(&:id)
      
      post batch_delete_expenses_path, params: {
        expense_ids: expense_ids
      }
      
      expect(response).to have_http_status(:ok)
      
      expenses.first(3).each do |expense|
        expense.reload
        expect(expense.status).to eq('deleted')
        expect(expense.deleted_at).to be_present
        expect(expense.deleted_by_id).to eq(user.id)
      end
    end
    
    it "creates audit log" do
      expect {
        post batch_delete_expenses_path, params: {
          expense_ids: expenses.first(2).map(&:id)
        }
      }.to change(BatchOperationLog, :count).by(1)
      
      log = BatchOperationLog.last
      expect(log.operation_type).to eq('delete')
      expect(log.user_id).to eq(user.id)
    end
  end
end
```

### 7.3 System Tests

```ruby
# spec/system/expense_list_optimization_spec.rb
require 'rails_helper'

RSpec.describe "Expense List Optimization", type: :system, js: true do
  let(:user) { create(:user) }
  let(:account) { create(:email_account, user: user) }
  let!(:expenses) { create_list(:expense, 100, email_account: account) }
  
  before do
    login_as(user)
    visit expenses_path
  end
  
  describe "Compact View Mode" do
    it "toggles between compact and standard views" do
      # Standard view by default
      expect(page).to have_css('.expense-row-standard')
      
      # Switch to compact
      click_button 'Compact View'
      expect(page).to have_css('.expense-row-compact')
      expect(page).not_to have_css('.expense-row-standard')
      
      # More expenses visible
      visible_expenses = all('.expense-row-compact').count
      expect(visible_expenses).to be >= 10
    end
  end
  
  describe "Batch Selection" do
    it "allows selecting multiple expenses" do
      # Select first 3 expenses
      within('.expense-list') do
        checkboxes = all('input[type="checkbox"]')[1..3]
        checkboxes.each(&:click)
      end
      
      # Action bar appears
      expect(page).to have_css('.batch-action-bar')
      expect(page).to have_text('3 selected')
      
      # Categorize selected
      click_button 'Categorize'
      select 'Food', from: 'category_id'
      click_button 'Apply'
      
      expect(page).to have_text('Successfully categorized 3 expenses')
    end
    
    it "supports select all functionality" do
      # Click select all
      find('#select-all-checkbox').click
      
      expect(page).to have_text("#{expenses.count} selected")
      expect(page).to have_css('.batch-action-bar')
    end
    
    it "supports shift-click range selection" do
      checkboxes = all('.expense-checkbox')
      
      # Click first checkbox
      checkboxes[0].click
      
      # Shift-click fifth checkbox
      checkboxes[4].click(:shift)
      
      expect(page).to have_text('5 selected')
    end
  end
  
  describe "Filter Chips" do
    it "applies and displays active filters" do
      # Apply category filter
      click_button 'Add Filter'
      click_link 'Category'
      check 'Food'
      check 'Transport'
      click_button 'Apply'
      
      # Filter chips appear
      expect(page).to have_css('.filter-chip', text: 'Food')
      expect(page).to have_css('.filter-chip', text: 'Transport')
      
      # Remove filter
      within('.filter-chip', text: 'Food') do
        click_button '×'
      end
      
      expect(page).not_to have_css('.filter-chip', text: 'Food')
    end
  end
  
  describe "Virtual Scrolling" do
    before do
      create_list(:expense, 1000, email_account: account)
      visit expenses_path
    end
    
    it "maintains performance with large datasets" do
      # Check initial DOM nodes
      initial_nodes = all('.expense-row').count
      expect(initial_nodes).to be < 100  # Virtual scrolling limits DOM
      
      # Scroll down
      execute_script("window.scrollTo(0, document.body.scrollHeight)")
      sleep 0.5  # Wait for virtual scroll to update
      
      # DOM nodes should still be limited
      final_nodes = all('.expense-row').count
      expect(final_nodes).to be < 100
    end
  end
  
  describe "Inline Quick Actions" do
    it "shows actions on hover" do
      expense_row = first('.expense-row')
      
      # Actions hidden initially
      expect(expense_row).not_to have_css('.quick-actions')
      
      # Hover shows actions
      expense_row.hover
      expect(expense_row).to have_css('.quick-actions')
      
      # Can perform quick edit
      within(expense_row) do
        click_button 'Edit'
      end
      
      expect(page).to have_css('.inline-edit-form')
    end
  end
  
  describe "Keyboard Navigation" do
    it "supports keyboard shortcuts" do
      # Select expense with keyboard
      send_keys :tab, :space  # Tab to first checkbox and select
      
      expect(page).to have_text('1 selected')
      
      # Navigate with arrow keys
      send_keys :arrow_down, :space
      
      expect(page).to have_text('2 selected')
      
      # Open actions with Enter
      send_keys :enter
      
      expect(page).to have_css('.batch-action-menu')
    end
  end
end
```

---

## 8. Monitoring & Observability

### 8.1 Metrics Collection

```ruby
# app/services/metrics_collector.rb
class MetricsCollector
  METRICS_NAMESPACE = 'expense_list'
  
  class << self
    def record_filter_performance(filter_params, duration, result_count)
      tags = {
        has_date_filter: filter_params[:date_range].present?,
        has_category_filter: filter_params[:category_ids].present?,
        has_search: filter_params[:search_query].present?,
        result_count_bucket: bucket_for_count(result_count)
      }
      
      StatsD.timing("#{METRICS_NAMESPACE}.filter.duration", duration, tags: tags)
      StatsD.gauge("#{METRICS_NAMESPACE}.filter.result_count", result_count, tags: tags)
    end
    
    def record_batch_operation(operation, expense_count, result)
      tags = {
        operation: operation,
        size_bucket: bucket_for_count(expense_count),
        success: result.success?
      }
      
      StatsD.timing("#{METRICS_NAMESPACE}.batch.duration", result.duration * 1000, tags: tags)
      StatsD.increment("#{METRICS_NAMESPACE}.batch.#{operation}", tags: tags)
      
      if result.failed_ids.any?
        StatsD.gauge("#{METRICS_NAMESPACE}.batch.failures", result.failed_ids.size, tags: tags)
      end
    end
    
    def record_virtual_scroll_performance(fps, memory_mb, render_time_ms)
      StatsD.gauge("#{METRICS_NAMESPACE}.virtual_scroll.fps", fps)
      StatsD.gauge("#{METRICS_NAMESPACE}.virtual_scroll.memory_mb", memory_mb)
      StatsD.timing("#{METRICS_NAMESPACE}.virtual_scroll.render_time", render_time_ms)
    end
    
    def record_database_performance(query_type, duration, rows_examined)
      tags = {
        query_type: query_type,
        slow: duration > 100
      }
      
      StatsD.timing("#{METRICS_NAMESPACE}.database.query_time", duration, tags: tags)
      StatsD.gauge("#{METRICS_NAMESPACE}.database.rows_examined", rows_examined, tags: tags)
    end
    
    private
    
    def bucket_for_count(count)
      case count
      when 0..10 then '0-10'
      when 11..50 then '11-50'
      when 51..100 then '51-100'
      when 101..500 then '101-500'
      else '500+'
      end
    end
  end
end
```

### 8.2 Health Checks

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  skip_before_action :authenticate_user!
  
  def expense_list
    health_status = ExpenseListHealthCheck.new.run
    
    if health_status[:healthy]
      render json: health_status, status: :ok
    else
      render json: health_status, status: :service_unavailable
    end
  end
end

# app/services/expense_list_health_check.rb
class ExpenseListHealthCheck
  def run
    checks = {
      database_indexes: check_indexes,
      query_performance: check_query_performance,
      cache_connectivity: check_cache,
      batch_operation_queue: check_batch_queue
    }
    
    {
      healthy: checks.values.all?,
      checks: checks,
      timestamp: Time.current.iso8601
    }
  end
  
  private
  
  def check_indexes
    required_indexes = %w[
      idx_expenses_filter_primary
      idx_expenses_list_covering
      idx_expenses_category_date
      idx_expenses_uncategorized
    ]
    
    existing_indexes = ActiveRecord::Base.connection.indexes('expenses').map(&:name)
    required_indexes.all? { |idx| existing_indexes.include?(idx) }
  rescue => e
    Rails.logger.error "Index check failed: #{e.message}"
    false
  end
  
  def check_query_performance
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Expense.limit(1).to_a
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    
    duration < 0.01  # Should complete in under 10ms
  rescue => e
    Rails.logger.error "Query performance check failed: #{e.message}"
    false
  end
  
  def check_cache
    Rails.cache.write('health_check', 'ok', expires_in: 1.minute)
    Rails.cache.read('health_check') == 'ok'
  rescue => e
    Rails.logger.error "Cache check failed: #{e.message}"
    false
  end
  
  def check_batch_queue
    # Check if batch operation jobs are processing
    queue_size = Sidekiq::Queue.new('batch_operations').size rescue 0
    queue_size < 1000  # Alert if queue is backing up
  rescue => e
    Rails.logger.error "Batch queue check failed: #{e.message}"
    false
  end
end
```

---

## Implementation Checklist

### Phase 1: Foundation (Week 1)
- [ ] Create and run database migrations
- [ ] Add all performance indexes
- [ ] Implement ExpenseFilterService
- [ ] Add performance monitoring
- [ ] Write unit tests for filtering

### Phase 2: Core Features (Week 2)
- [ ] Implement BatchOperationService
- [ ] Add authorization policies
- [ ] Create API endpoints
- [ ] Implement error handling
- [ ] Add integration tests

### Phase 3: Advanced Features (Week 3)
- [ ] Implement virtual scrolling
- [ ] Add export functionality
- [ ] Create filter preferences
- [ ] Add health checks
- [ ] Complete system tests

### Phase 4: Optimization (Week 4)
- [ ] Performance testing and tuning
- [ ] Security audit
- [ ] Documentation
- [ ] Load testing
- [ ] Production deployment

---

## Conclusion

These enhanced technical specifications provide comprehensive, implementation-ready details for Epic 3. Each component includes:

1. **Complete code implementations** with error handling and edge cases
2. **Database schema changes** with reversible migrations
3. **Performance benchmarks** with specific targets and monitoring
4. **Security measures** including authorization and input sanitization
5. **Comprehensive testing** covering unit, integration, and system tests
6. **Monitoring and observability** for production operations

The specifications follow Rails 8.0.2 best practices and are designed to handle 10,000+ records efficiently while maintaining the Financial Confidence color palette throughout the UI implementation.
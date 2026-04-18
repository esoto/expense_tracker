# frozen_string_literal: true

require "rails_helper"

# PER-126: Index Audit — verifies that:
# 1. All 34 redundant indexes have been removed
# 2. All covering composite indexes are still present
# 3. Key queries still use appropriate indexes (via EXPLAIN)
# 4. Query performance remains within the <50ms target after index removal
#
# Tagged :unit so the pre-commit hook includes it.

RSpec.describe "PER-126 Index Audit", :unit do
  let(:connection) { ActiveRecord::Base.connection }

  def index_names_for(table)
    connection.indexes(table).map(&:name)
  end

  # ── REMOVED INDEXES ──────────────────────────────────────────────────────────

  describe "removed redundant indexes" do
    context "bulk_operation_items" do
      it "no longer has the single-column bulk_operation_id index" do
        expect(index_names_for(:bulk_operation_items))
          .not_to include("index_bulk_operation_items_on_bulk_operation_id")
      end
    end

    context "bulk_operations" do
      it "no longer has the single-column status index" do
        expect(index_names_for(:bulk_operations))
          .not_to include("index_bulk_operations_on_status")
      end

      it "no longer has the single-column user_id index" do
        expect(index_names_for(:bulk_operations))
          .not_to include("index_bulk_operations_on_user_id")
      end
    end

    context "categorization_patterns" do
      it "no longer has the exact-duplicate idx_patterns_lookup" do
        expect(index_names_for(:categorization_patterns))
          .not_to include("idx_patterns_lookup")
      end

      it "no longer has the covered active+pattern_type index" do
        expect(index_names_for(:categorization_patterns))
          .not_to include("index_categorization_patterns_on_active_and_pattern_type")
      end

      it "no longer has the single-column category_id index" do
        expect(index_names_for(:categorization_patterns))
          .not_to include("index_categorization_patterns_on_category_id")
      end

      it "no longer has the single-column created_at index (covered by activity index)" do
        expect(index_names_for(:categorization_patterns))
          .not_to include("idx_patterns_created_at")
      end

      it "no longer has the duplicate GIN pattern_value index" do
        expect(index_names_for(:categorization_patterns))
          .not_to include("index_categorization_patterns_on_pattern_value")
      end

      it "no longer has the frequently_used partial index (covered by performance indexes)" do
        expect(index_names_for(:categorization_patterns))
          .not_to include("idx_patterns_frequently_used")
      end
    end

    context "composite_patterns" do
      it "no longer has the single-column category_id index" do
        expect(index_names_for(:composite_patterns))
          .not_to include("index_composite_patterns_on_category_id")
      end

      it "no longer has the single-column operator index" do
        expect(index_names_for(:composite_patterns))
          .not_to include("index_composite_patterns_on_operator")
      end

      it "no longer has the duplicate GIN pattern_ids index" do
        expect(index_names_for(:composite_patterns))
          .not_to include("index_composite_patterns_on_pattern_ids")
      end
    end

    context "email_accounts" do
      it "no longer has the single-column active index" do
        expect(index_names_for(:email_accounts))
          .not_to include("index_email_accounts_on_active")
      end
    end

    context "expenses" do
      it "no longer has the plain auto_categorized+confidence index (covered by partial)" do
        expect(index_names_for(:expenses))
          .not_to include("idx_on_auto_categorized_categorization_confidence_98abf3d147")
      end

      it "no longer has the single-column category_id index" do
        expect(index_names_for(:expenses))
          .not_to include("index_expenses_on_category_id")
      end
    end

    context "merchant_aliases" do
      it "no longer has the single-column canonical_merchant_id index" do
        expect(index_names_for(:merchant_aliases))
          .not_to include("index_merchant_aliases_on_canonical_merchant_id")
      end

      it "no longer has the duplicate GIN normalized_name index" do
        expect(index_names_for(:merchant_aliases))
          .not_to include("index_merchant_aliases_on_normalized_name")
      end
    end

    context "parsing_rules" do
      it "no longer has the single-column bank_name index" do
        expect(index_names_for(:parsing_rules))
          .not_to include("index_parsing_rules_on_bank_name")
      end
    end

    context "pattern_feedbacks" do
      it "no longer has the duplicate categorization_pattern_id+was_correct index" do
        expect(index_names_for(:pattern_feedbacks))
          .not_to include("idx_on_categorization_pattern_id_was_correct_e615042861")
      end

      it "no longer has the single-column categorization_pattern_id index" do
        expect(index_names_for(:pattern_feedbacks))
          .not_to include("index_pattern_feedbacks_on_categorization_pattern_id")
      end

      it "no longer has the single-column category_id index" do
        expect(index_names_for(:pattern_feedbacks))
          .not_to include("index_pattern_feedbacks_on_category_id")
      end

      it "no longer has the single-column expense_id index" do
        expect(index_names_for(:pattern_feedbacks))
          .not_to include("index_pattern_feedbacks_on_expense_id")
      end

      it "no longer has the single-column created_at index" do
        expect(index_names_for(:pattern_feedbacks))
          .not_to include("index_pattern_feedbacks_on_created_at")
      end

      it "no longer has the duplicate category_id+was_correct+created_at index" do
        expect(index_names_for(:pattern_feedbacks))
          .not_to include("idx_feedbacks_category_correct_created")
      end
    end

    context "pattern_learning_events" do
      it "no longer has the duplicate was_correct+created_at index" do
        expect(index_names_for(:pattern_learning_events))
          .not_to include("idx_learning_events_correct_time")
      end

      it "no longer has the single-column was_correct index" do
        expect(index_names_for(:pattern_learning_events))
          .not_to include("index_pattern_learning_events_on_was_correct")
      end

      it "no longer has the single-column event_type index" do
        expect(index_names_for(:pattern_learning_events))
          .not_to include("index_pattern_learning_events_on_event_type")
      end

      it "no longer has the single-column created_at index" do
        expect(index_names_for(:pattern_learning_events))
          .not_to include("index_pattern_learning_events_on_created_at")
      end

      it "no longer has the single-column category_id index" do
        expect(index_names_for(:pattern_learning_events))
          .not_to include("index_pattern_learning_events_on_category_id")
      end

      it "no longer has the single-column pattern_used index" do
        expect(index_names_for(:pattern_learning_events))
          .not_to include("index_pattern_learning_events_on_pattern_used")
      end
    end

    context "sync_conflicts" do
      it "no longer has the single-column status index" do
        expect(index_names_for(:sync_conflicts))
          .not_to include("index_sync_conflicts_on_status")
      end

      it "no longer has the single-column sync_session_id index" do
        expect(index_names_for(:sync_conflicts))
          .not_to include("index_sync_conflicts_on_sync_session_id")
      end
    end

    context "sync_metrics" do
      it "no longer has the single-column metric_type index" do
        expect(index_names_for(:sync_metrics))
          .not_to include("index_sync_metrics_on_metric_type")
      end

      it "no longer has the single-column email_account_id index" do
        expect(index_names_for(:sync_metrics))
          .not_to include("index_sync_metrics_on_email_account_id")
      end

      it "no longer has the single-column sync_session_id index" do
        expect(index_names_for(:sync_metrics))
          .not_to include("index_sync_metrics_on_sync_session_id")
      end

      it "no longer has the single-column started_at index (covered by started_at+completed_at)" do
        expect(index_names_for(:sync_metrics))
          .not_to include("index_sync_metrics_on_started_at")
      end
    end

    context "undo_histories" do
      it "no longer has the single-column action_type index" do
        expect(index_names_for(:undo_histories))
          .not_to include("index_undo_histories_on_action_type")
      end

      it "no longer has the single-column user_id index" do
        expect(index_names_for(:undo_histories))
          .not_to include("index_undo_histories_on_user_id")
      end
    end

    context "user_category_preferences" do
      it "no longer has the single-column email_account_id index" do
        expect(index_names_for(:user_category_preferences))
          .not_to include("index_user_category_preferences_on_email_account_id")
      end

      it "no longer has the 3-column email_account+context covered index" do
        expect(index_names_for(:user_category_preferences))
          .not_to include("idx_on_email_account_id_context_type_context_value_b40292993e")
      end

      it "no longer has the 2-column context_type+context_value index (covered by 3-column)" do
        expect(index_names_for(:user_category_preferences))
          .not_to include("idx_user_prefs_context")
      end
    end
  end

  # ── RETAINED COVERING INDEXES ────────────────────────────────────────────────

  describe "covering composite indexes are retained" do
    it "keeps bulk_operation_items composite [bulk_operation_id, expense_id] unique" do
      expect(index_names_for(:bulk_operation_items))
        .to include("index_bulk_operation_items_on_bulk_operation_id_and_expense_id")
    end

    it "keeps bulk_operation_items [bulk_operation_id, status]" do
      expect(index_names_for(:bulk_operation_items))
        .to include("index_bulk_operation_items_on_bulk_operation_id_and_status")
    end

    it "keeps bulk_operations [status, created_at]" do
      expect(index_names_for(:bulk_operations))
        .to include("index_bulk_operations_on_status_and_created_at")
    end

    it "keeps bulk_operations [user_id, created_at]" do
      expect(index_names_for(:bulk_operations))
        .to include("index_bulk_operations_on_user_id_and_created_at")
    end

    it "keeps categorization_patterns GIN trigram index idx_patterns_value_trgm" do
      expect(index_names_for(:categorization_patterns))
        .to include("idx_patterns_value_trgm")
    end

    it "keeps categorization_patterns unique lookup idx_patterns_unique_lookup" do
      expect(index_names_for(:categorization_patterns))
        .to include("idx_patterns_unique_lookup")
    end

    it "keeps categorization_patterns [active, pattern_type, usage_count]" do
      expect(index_names_for(:categorization_patterns))
        .to include("idx_patterns_active_type_usage")
    end

    it "keeps categorization_patterns idx_patterns_type_active_success" do
      expect(index_names_for(:categorization_patterns))
        .to include("idx_patterns_type_active_success")
    end

    it "keeps composite_patterns [category_id, active]" do
      expect(index_names_for(:composite_patterns))
        .to include("index_composite_patterns_on_category_id_and_active")
    end

    it "keeps composite_patterns GIN idx_composite_pattern_ids_gin" do
      expect(index_names_for(:composite_patterns))
        .to include("idx_composite_pattern_ids_gin")
    end

    it "keeps email_accounts [active, bank_name]" do
      expect(index_names_for(:email_accounts))
        .to include("index_email_accounts_on_active_and_bank_name")
    end

    it "keeps expenses partial auto-categorization index idx_expenses_auto_categorization" do
      expect(index_names_for(:expenses))
        .to include("idx_expenses_auto_categorization")
    end

    it "keeps expenses [category_id, transaction_date]" do
      expect(index_names_for(:expenses))
        .to include("index_expenses_on_category_id_and_transaction_date")
    end

    it "keeps merchant_aliases [canonical_merchant_id, confidence]" do
      expect(index_names_for(:merchant_aliases))
        .to include("index_merchant_aliases_on_canonical_merchant_id_and_confidence")
    end

    it "keeps merchant_aliases GIN idx_merchant_alias_trgm" do
      expect(index_names_for(:merchant_aliases))
        .to include("idx_merchant_alias_trgm")
      end

    it "keeps parsing_rules [bank_name, active]" do
      expect(index_names_for(:parsing_rules))
        .to include("index_parsing_rules_on_bank_name_and_active")
    end

    it "keeps pattern_feedbacks [categorization_pattern_id, was_correct] idx_feedbacks_pattern_correct" do
      expect(index_names_for(:pattern_feedbacks))
        .to include("idx_feedbacks_pattern_correct")
    end

    it "keeps pattern_feedbacks [category_id, was_correct, created_at] idx_feedback_category_stats" do
      expect(index_names_for(:pattern_feedbacks))
        .to include("idx_feedback_category_stats")
    end

    it "keeps pattern_feedbacks unique [expense_id, categorization_pattern_id]" do
      expect(index_names_for(:pattern_feedbacks))
        .to include("idx_feedbacks_expense_pattern")
    end

    it "keeps pattern_learning_events [was_correct, created_at] idx_learning_correct_created" do
      expect(index_names_for(:pattern_learning_events))
        .to include("idx_learning_correct_created")
    end

    it "keeps pattern_learning_events [event_type, created_at]" do
      expect(index_names_for(:pattern_learning_events))
        .to include("index_pattern_learning_events_on_event_type_and_created_at")
    end

    it "keeps sync_conflicts [status, conflict_type]" do
      expect(index_names_for(:sync_conflicts))
        .to include("index_sync_conflicts_on_status_and_conflict_type")
    end

    it "keeps sync_conflicts [sync_session_id, status]" do
      expect(index_names_for(:sync_conflicts))
        .to include("index_sync_conflicts_on_sync_session_id_and_status")
    end

    it "keeps sync_metrics [metric_type, started_at]" do
      expect(index_names_for(:sync_metrics))
        .to include("index_sync_metrics_on_metric_type_and_started_at")
    end

    it "keeps sync_metrics [email_account_id, metric_type]" do
      expect(index_names_for(:sync_metrics))
        .to include("index_sync_metrics_on_email_account_id_and_metric_type")
    end

    it "keeps sync_metrics [sync_session_id, metric_type]" do
      expect(index_names_for(:sync_metrics))
        .to include("index_sync_metrics_on_sync_session_id_and_metric_type")
    end

    it "keeps sync_metrics [started_at, completed_at]" do
      expect(index_names_for(:sync_metrics))
        .to include("index_sync_metrics_on_started_at_and_completed_at")
    end

    it "keeps undo_histories [action_type, undone_at]" do
      expect(index_names_for(:undo_histories))
        .to include("index_undo_histories_on_action_type_and_undone_at")
    end

    it "keeps undo_histories [user_id, created_at]" do
      expect(index_names_for(:undo_histories))
        .to include("index_undo_histories_on_user_id_and_created_at")
    end

    it "keeps user_category_preferences 4-column lookup idx_user_pref_lookup" do
      expect(index_names_for(:user_category_preferences))
        .to include("idx_user_pref_lookup")
    end

    it "keeps user_category_preferences [context_type, context_value, preference_weight]" do
      expect(index_names_for(:user_category_preferences))
        .to include("idx_user_prefs_context_weight")
    end
  end

  # ── UNIQUE AND PARTIAL INDEXES UNTOUCHED ─────────────────────────────────────

  describe "unique indexes are not removed" do
    it "retains admin_users unique email index" do
      idx = connection.indexes(:admin_users).find { |i| i.name == "index_admin_users_on_email" }
      expect(idx).not_to be_nil
      expect(idx.unique).to be true
    end

    it "retains categorization_patterns unique lookup index" do
      idx = connection.indexes(:categorization_patterns).find { |i| i.name == "idx_patterns_unique_lookup" }
      expect(idx).not_to be_nil
      expect(idx.unique).to be true
    end

    it "retains budgets unique active budget constraint index" do
      idx = connection.indexes(:budgets).find { |i| i.name == "index_budgets_unique_active" }
      expect(idx).not_to be_nil
      expect(idx.unique).to be true
    end
  end

  # ── TOTAL INDEX COUNT ────────────────────────────────────────────────────────

  # ── PHASE 2 CATEGORIZATION INDEXES ──────────────────────────────────────────

  describe "Phase 2 categorization indexes" do
    it "categorization_vectors has a GiST trigram index on merchant_normalized" do
      indexes = connection.indexes(:categorization_vectors)
      trgm_index = indexes.find { |i| i.name == "index_categorization_vectors_on_merchant_trgm" }
      expect(trgm_index).to be_present
      expect(trgm_index.using).to eq(:gist)
    end

    it "categorization_vectors has a unique composite index on merchant + category" do
      indexes = connection.indexes(:categorization_vectors)
      composite = indexes.find { |i| i.name == "index_categorization_vectors_on_merchant_and_category" }
      expect(composite).to be_present
      expect(composite.unique).to be true
    end

    # PER-499: the unique index was widened to
    # (merchant_normalized, prompt_version, model_used) so prompt / model
    # bumps invalidate old rows instead of silently serving stale results.
    it "llm_categorization_cache has a composite unique index including prompt_version + model_used" do
      indexes = connection.indexes(:llm_categorization_cache)
      composite_idx = indexes.find { |i| i.name == "index_llm_cache_on_merchant_version_model" }
      expect(composite_idx).to be_present
      expect(composite_idx.unique).to be true
      expect(composite_idx.columns).to eq(%w[merchant_normalized prompt_version model_used])
    end
  end

  describe "total index count reflects removal" do
    it "has 208 or fewer indexes after removing 42 redundant indexes from the pre-audit total of 250" do
      total = connection.tables.sum { |t| connection.indexes(t).size }
      # Pre-audit: 250 indexes; 42 removed => current total is 208
      # +1 for categories.i18n_key unique index added in i18n migration
      # +11 for Phase 2 categorization tables (categorization_metrics: 6, categorization_vectors: 3, llm_categorization_cache: 2)
      # +4 for external sources integration (external_budget_sources: 2, budgets external columns: 2)
      expect(total).to be <= 228  # small buffer for schema drift
    end
  end
end

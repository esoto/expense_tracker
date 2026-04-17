# frozen_string_literal: true

# PER-499 (H1): add prompt_version to the LLM cache key so stale entries age
# out when prompt logic or model version changes. The pre-existing unique
# index on (merchant_normalized) meant a single prompt tweak could pin a
# wrong classification in cache forever (refresh_ttl! on every hit extended
# its life indefinitely).
#
# After this migration the cache key is (merchant_normalized, prompt_version,
# model_used). Bumping PROMPT_VERSION in PromptBuilder makes every lookup
# miss, a fresh LLM call populates a new row, and the old row ages out via
# the existing expires_at / LlmCacheCleanupJob path.
class AddPromptVersionToLlmCategorizationCache < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Default "v1" for existing rows — every row pre-dates this migration and
    # was produced by the v1 prompt pipeline. New rows get the current
    # PROMPT_VERSION on insert (see LlmStrategy#store_cache).
    add_column :llm_categorization_cache, :prompt_version, :string, default: "v1", null: false

    # Swap the unique index: add the composite FIRST, then drop the old
    # single-column one. Reverse of the naive order on purpose — between
    # `remove` and `add` (both concurrent, minutes on a large table) there
    # would otherwise be a window with no unique constraint on
    # merchant_normalized, during which concurrent writes could insert
    # duplicates and then cause the CREATE UNIQUE INDEX CONCURRENTLY to
    # fail and leave an INVALID index behind. The brief both-indexes-live
    # state is ~10 MB extra and has no correctness issue because every
    # existing row has prompt_version="v1" + a single model_used, so the
    # composite is functionally equivalent to the single-column index for
    # legacy rows.
    add_index :llm_categorization_cache,
              %i[merchant_normalized prompt_version model_used],
              unique: true,
              name: :index_llm_cache_on_merchant_version_model,
              algorithm: :concurrently

    remove_index :llm_categorization_cache,
                 name: :index_llm_cache_on_merchant_normalized,
                 algorithm: :concurrently
  end

  def down
    add_index :llm_categorization_cache,
              :merchant_normalized,
              unique: true,
              name: :index_llm_cache_on_merchant_normalized,
              algorithm: :concurrently

    remove_index :llm_categorization_cache,
                 name: :index_llm_cache_on_merchant_version_model,
                 algorithm: :concurrently

    remove_column :llm_categorization_cache, :prompt_version
  end
end

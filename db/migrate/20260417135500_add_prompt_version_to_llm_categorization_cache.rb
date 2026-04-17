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

    # Swap the unique index: drop (merchant_normalized), add the composite.
    # `concurrently` on both so writes continue during deploy.
    remove_index :llm_categorization_cache,
                 name: :index_llm_cache_on_merchant_normalized,
                 algorithm: :concurrently

    add_index :llm_categorization_cache,
              %i[merchant_normalized prompt_version model_used],
              unique: true,
              name: :index_llm_cache_on_merchant_version_model,
              algorithm: :concurrently
  end

  def down
    remove_index :llm_categorization_cache,
                 name: :index_llm_cache_on_merchant_version_model,
                 algorithm: :concurrently

    add_index :llm_categorization_cache,
              :merchant_normalized,
              unique: true,
              name: :index_llm_cache_on_merchant_normalized,
              algorithm: :concurrently

    remove_column :llm_categorization_cache, :prompt_version
  end
end

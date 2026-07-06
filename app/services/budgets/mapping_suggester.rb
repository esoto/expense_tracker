# frozen_string_literal: true

module Services::Budgets
  # Tiered budget-name → category suggester (spec:
  # 2026-07-05-budget-mapping-suggester-design.md). Tier 0 applies cached
  # exact/user mappings; tier 1 auto-applies exact normalized name matches;
  # tier 2 stores FuzzyMatcher suggestions; tier 3 batches every remaining
  # name into one LLM call. Only exact/user tiers ever mutate budgets.
  class MappingSuggester
    FUZZY_MIN_CONFIDENCE = 0.6
    LLM_CONFIDENCE = 0.75

    def self.call(budgets, llm_resolver: nil)
      new(budgets, llm_resolver: llm_resolver).call
    end

    def initialize(budgets, llm_resolver: nil)
      @budgets = Array(budgets)
      @llm_resolver = llm_resolver || MappingLlmResolver.new
      @applied = 0
      @suggested = 0
      @unresolved = []
    end

    def call
      @budgets.group_by(&:user).each do |user, user_budgets|
        process_user(user, user_budgets)
      end
      { applied: @applied, suggested: @suggested, unresolved: @unresolved }
    end

    private

    def process_user(user, user_budgets)
      categories = Category.visible_to(user).to_a
      pending = {}

      user_budgets.each do |budget|
        next if budget.categories.any? || !budget.spend_tracking?

        normalized = BudgetNameMapping.normalize(budget.name)
        next if try_cache(user, budget, normalized)
        next if try_exact(user, budget, normalized, categories)
        next if try_fuzzy(user, normalized, categories)

        (pending[normalized] ||= []) << budget
      end

      resolve_with_llm(user, pending, categories) if pending.any?
    end

    # Any existing row short-circuits the pipeline — this is what bounds LLM
    # cost to once per name, and guarantees a user-confirmed row can never be
    # overwritten by a lower tier. Deliberate tradeoff: a name cached as a
    # fuzzy/llm suggestion will NOT auto-upgrade if a new exactly-matching
    # category appears later; the review UI (or deleting the mapping row)
    # resolves it.
    def try_cache(user, budget, normalized)
      mapping = BudgetNameMapping.for_lookup(user, normalized).first
      return false unless mapping

      apply!(budget, mapping) if mapping.auto_applicable?
      true
    end

    def try_exact(user, budget, normalized, categories)
      category = categories.find { |c| BudgetNameMapping.normalize(c.display_name) == normalized ||
                                       BudgetNameMapping.normalize(c.name) == normalized }
      return false unless category

      mapping = upsert_mapping(user, normalized, category: category, kind: :category,
                               source: :exact, confidence: 1.0)
      apply!(budget, mapping)
      true
    end

    def try_fuzzy(user, normalized, categories)
      candidates = categories.map { |c| { id: c.id, text: c.display_name, object: c } }
      result = fuzzy_matcher.match(normalized, candidates)
      best = result.respond_to?(:matches) ? result.matches.first : nil
      return false unless best && best[:score].to_f >= FUZZY_MIN_CONFIDENCE
      return false unless word_containment?(normalized, BudgetNameMapping.normalize(best[:object].display_name))

      upsert_mapping(user, normalized, category: best[:object], kind: :category,
                     source: :fuzzy, confidence: best[:score].to_f.round(3))
      @suggested += 1
      true
    end

    # Similarity scores alone cannot separate real matches from lookalike
    # Spanish words at these lengths — prod run 2026-07-06 scored
    # "comida"→"Compras" at 0.82 (garbage) while the correct
    # "impuestos de la casa"→"Impuestos" scored 0.69. A fuzzy hit is only
    # trusted when the two names share a whole word (≥4 chars); everything
    # else falls through to the LLM tier, which handles semantics.
    def word_containment?(a, b)
      (a.split & b.split).any? { |w| w.length >= 4 }
    end

    def resolve_with_llm(user, pending, categories)
      verdicts = @llm_resolver.resolve(names: pending.keys, categories: categories, user: user)
      pending.each do |normalized, _budgets|
        verdict = verdicts[normalized]
        if verdict.nil?
          @unresolved << normalized
          next
        end
        upsert_mapping(user, normalized, category: verdict[:category], kind: verdict[:kind],
                       source: :llm, confidence: LLM_CONFIDENCE)
        @suggested += 1
      end
    rescue StandardError => e
      Rails.logger.error("[MappingSuggester] LLM tier failed, leaving #{pending.size} names unresolved: #{e.message}")
      @unresolved.concat(pending.keys)
    end

    def apply!(budget, mapping)
      if mapping.kind_allocation?
        budget.update!(spend_tracking: false)
      else
        BudgetCategory.find_or_create_by!(budget: budget, category: mapping.category)
      end
      @applied += 1
    end

    def upsert_mapping(user, normalized, attrs)
      mapping = BudgetNameMapping.for_lookup(user, normalized).first_or_initialize
      mapping.update!(attrs)
      mapping
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      # Concurrent suggester runs for the same user (one job per email
      # account) can race on the unique (user_id, normalized_name) index.
      # The winner's row stands — same never-raise posture as the LLM tier.
      BudgetNameMapping.for_lookup(user, normalized).first!
    end

    def fuzzy_matcher
      @fuzzy_matcher ||= Services::Categorization::Matchers::FuzzyMatcher.new(
        algorithms: [ :jaro_winkler, :trigram ], min_confidence: FUZZY_MIN_CONFIDENCE, max_results: 1
      )
    end
  end
end

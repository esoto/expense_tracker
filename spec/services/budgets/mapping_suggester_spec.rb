# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Budgets::MappingSuggester, :unit do
  let(:user) { create(:user) }
  let(:email_account) { create(:email_account, user: user) }
  let(:null_llm) { instance_double(Services::Budgets::MappingLlmResolver, resolve: {}) }

  def external_budget(name)
    create(:budget, email_account: email_account, user: user, name: name,
           external_source: "salary_calculator", external_id: rand(10_000), category: nil)
  end

  def call(budgets)
    described_class.call(budgets, llm_resolver: null_llm)
  end

  describe "tier 0 — cache" do
    it "auto-applies a user-confirmed mapping" do
      cat = create(:category, name: "Servicios", user: nil)
      create(:budget_name_mapping, :confirmed, user: user, normalized_name: "condominio", category: cat)
      budget = external_budget("Condominio")

      result = call([ budget ])

      expect(budget.reload.categories).to contain_exactly(cat)
      expect(result[:applied]).to eq(1)
    end

    it "auto-applies a confirmed allocation by disabling spend_tracking" do
      create(:budget_name_mapping, :allocation, :confirmed, user: user, normalized_name: "retirement")
      budget = external_budget("Retirement")

      call([ budget ])

      expect(budget.reload.spend_tracking).to be(false)
      expect(budget.reload.categories).to be_empty
    end

    it "does nothing for a cached fuzzy suggestion (already suggested)" do
      cat = create(:category, name: "Electricidad", user: nil)
      create(:budget_name_mapping, user: user, normalized_name: "luz", category: cat, source: :fuzzy)
      budget = external_budget("Luz")

      result = call([ budget ])

      expect(budget.reload.categories).to be_empty
      expect(result[:applied]).to eq(0)
      expect(result[:suggested]).to eq(0) # no new row written
    end
  end

  describe "tier 1 — exact match" do
    it "auto-applies and records an exact normalized name match" do
      cat = create(:category, name: "Agua", user: nil)
      budget = external_budget("Agua")

      result = call([ budget ])

      expect(budget.reload.categories).to contain_exactly(cat)
      mapping = BudgetNameMapping.find_by!(user: user, normalized_name: "agua")
      expect(mapping).to have_attributes(source: "exact", confidence: 1.0, category: cat)
      expect(result[:applied]).to eq(1)
    end

    it "matches accent-insensitively" do
      cat = create(:category, name: "Alimentación", user: nil)
      budget = external_budget("alimentacion")

      call([ budget ])

      expect(budget.reload.categories).to contain_exactly(cat)
    end
  end

  describe "tier 2 — fuzzy suggestion" do
    it "records a suggestion without applying for a close-but-inexact name" do
      cat = create(:category, name: "Impuestos", user: nil)
      budget = external_budget("Impuestos de la casa")

      result = call([ budget ])

      expect(budget.reload.categories).to be_empty
      mapping = BudgetNameMapping.find_by!(user: user, normalized_name: "impuestos de la casa")
      expect(mapping.source_fuzzy?).to be(true)
      expect(mapping.category).to eq(cat)
      expect(mapping.confidence).to be > 0.6
      expect(result[:suggested]).to eq(1)
    end
  end

  describe "tier 3 — delegation to llm resolver" do
    it "passes only unresolved names, with the user's visible categories" do
      create(:category, name: "Mascotas", user: nil)
      budget = external_budget("Pets")
      resolver = instance_double(Services::Budgets::MappingLlmResolver)
      expect(resolver).to receive(:resolve) do |names:, categories:, user: u|
        expect(names).to eq([ "pets" ])
        expect(categories.map(&:name)).to include("Mascotas")
        { "pets" => { category: Category.find_by!(name: "Mascotas"), kind: :category } }
      end

      result = described_class.call([ budget ], llm_resolver: resolver)

      mapping = BudgetNameMapping.find_by!(user: user, normalized_name: "pets")
      expect(mapping.source_llm?).to be(true)
      expect(mapping.confidence).to eq(0.75)
      expect(budget.reload.categories).to be_empty # llm results are suggestions only
      expect(result[:suggested]).to eq(1)
    end

    it "records llm allocation verdicts as suggestions (spend_tracking untouched)" do
      budget = external_budget("Familia Mariana")
      resolver = instance_double(Services::Budgets::MappingLlmResolver,
        resolve: { "familia mariana" => { category: nil, kind: :allocation } })

      described_class.call([ budget ], llm_resolver: resolver)

      mapping = BudgetNameMapping.find_by!(user: user, normalized_name: "familia mariana")
      expect(mapping.kind_allocation?).to be(true)
      expect(budget.reload.spend_tracking).to be(true) # not auto-applied
    end

    it "leaves names unresolved when the resolver returns nil for them" do
      budget = external_budget("Punta Leona")
      resolver = instance_double(Services::Budgets::MappingLlmResolver, resolve: {})

      result = described_class.call([ budget ], llm_resolver: resolver)

      expect(BudgetNameMapping.where(user: user).count).to eq(0)
      expect(result[:unresolved]).to eq([ "punta leona" ])
    end
  end

  describe "concurrent upsert race" do
    it "falls back to the winner's row instead of raising" do
      cat = create(:category, name: "Agua", user: nil)
      existing = create(:budget_name_mapping, user: user, normalized_name: "agua",
                        category: cat, source: :exact, confidence: 1.0)
      suggester = described_class.new([], llm_resolver: null_llm)
      # Simulate the race: first_or_initialize returns an unsaved duplicate
      # (as if the row did not exist yet), whose save trips the uniqueness
      # validation because `existing` was committed by a concurrent run.
      losing_duplicate = BudgetNameMapping.new(user: user, normalized_name: "agua")
      relation = instance_double(ActiveRecord::Relation)
      allow(BudgetNameMapping).to receive(:for_lookup).with(user, "agua").and_return(relation)
      allow(relation).to receive(:first_or_initialize).and_return(losing_duplicate)
      allow(relation).to receive(:first!).and_return(existing)

      result = suggester.send(:upsert_mapping, user, "agua",
                              category: cat, kind: :category, source: :exact, confidence: 1.0)

      expect(result).to eq(existing)
    end
  end

  it "skips budgets that already have categories and groups by user" do
    cat = create(:category, name: "Agua", user: nil)
    mapped = external_budget("Agua")
    BudgetCategory.create!(budget: mapped, category: cat)

    result = call([ mapped ])

    expect(result).to eq(applied: 0, suggested: 0, unresolved: [])
  end
end

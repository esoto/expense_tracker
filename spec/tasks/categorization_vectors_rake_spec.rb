# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "categorization:backfill_vectors", type: :task, unit: true do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/categorization_vectors", [ Rails.root.join("lib").to_s ])
    Rake::Task.define_task(:environment)
  end

  before { Rake::Task["categorization:backfill_vectors"].reenable }

  let(:task) { Rake::Task["categorization:backfill_vectors"] }
  let(:category) { create(:category) }
  let(:other_category) { create(:category) }

  it "creates vectors from expenses with merchant and category" do
    create(:expense, merchant_name: "Walmart", category: category, description: "Weekly groceries")
    create(:expense, merchant_name: "Walmart", category: category, description: "Food groceries shopping")

    expect { task.invoke }.to change(CategorizationVector, :count).by(1)

    vector = CategorizationVector.last
    expect(vector.merchant_normalized).to eq("walmart")
    expect(vector.category).to eq(category)
    expect(vector.occurrence_count).to eq(2)
  end

  it "creates separate vectors for different categories" do
    create(:expense, merchant_name: "Walmart", category: category)
    create(:expense, merchant_name: "Walmart", category: other_category)

    expect { task.invoke }.to change(CategorizationVector, :count).by(2)
  end

  it "skips expenses without a category" do
    create(:expense, merchant_name: "Walmart", category: nil)

    expect { task.invoke }.not_to change(CategorizationVector, :count)
  end

  it "skips expenses without a merchant_name" do
    create(:expense, merchant_name: nil, category: category)
    create(:expense, merchant_name: "", category: category)

    expect { task.invoke }.not_to change(CategorizationVector, :count)
  end

  it "extracts top 5 keywords from descriptions" do
    5.times { create(:expense, merchant_name: "Walmart", category: category, description: "weekly groceries food shopping supplies") }
    create(:expense, merchant_name: "Walmart", category: category, description: "extra rare unique")

    task.invoke

    vector = CategorizationVector.find_by(merchant_normalized: "walmart", category: category)
    expect(vector.description_keywords.size).to be <= 5
    expect(vector.description_keywords).to include("weekly", "groceries")
  end

  it "is idempotent — running twice produces the same result" do
    create(:expense, merchant_name: "Walmart", category: category, description: "groceries")

    task.invoke
    first_count = CategorizationVector.count
    first_vector = CategorizationVector.last.attributes.except("updated_at", "last_seen_at")

    task.reenable
    task.invoke
    second_count = CategorizationVector.count
    second_vector = CategorizationVector.last.attributes.except("updated_at", "last_seen_at")

    expect(second_count).to eq(first_count)
    expect(second_vector).to eq(first_vector)
  end
end

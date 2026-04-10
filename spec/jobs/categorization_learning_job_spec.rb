# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategorizationLearningJob, type: :job, unit: true do
  let(:job) { described_class.new }

  let(:category) { create(:category) }
  let(:other_category) { create(:category) }

  let(:updater_double) { instance_double(Services::Categorization::Learning::VectorUpdater) }

  before do
    allow(Services::Categorization::Learning::VectorUpdater)
      .to receive(:new).and_return(updater_double)
    allow(updater_double).to receive(:upsert)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe "#perform", unit: true do
    it "runs without error when no qualifying expenses exist" do
      expect { job.perform }.not_to raise_error
    end

    it "logs the count of processed expenses" do
      expect(Rails.logger).to receive(:info).with(/processed=0/)
      job.perform
    end

    context "with qualifying expenses (24h+ uncorrected)" do
      let!(:expense) do
        create(:expense, merchant_name: "Walmart", category: category, description: "groceries weekly")
      end

      let!(:metric) do
        create(:categorization_metric,
          expense: expense,
          category: category,
          was_corrected: false,
          created_at: 25.hours.ago)
      end

      it "calls VectorUpdater.upsert for qualifying expenses" do
        expect(updater_double).to receive(:upsert).with(
          merchant: "Walmart",
          category: category,
          description_keywords: array_including("groceries", "weekly")
        )
        job.perform
      end

      it "logs the count of processed expenses" do
        expect(Rails.logger).to receive(:info).with(/processed=1/)
        job.perform
      end
    end

    context "with expenses corrected within 24h (too recent)" do
      let!(:expense) do
        create(:expense, merchant_name: "Target", category: category)
      end

      let!(:metric) do
        create(:categorization_metric,
          expense: expense,
          category: category,
          was_corrected: false,
          created_at: 23.hours.ago)
      end

      it "does not process recent expenses" do
        expect(updater_double).not_to receive(:upsert)
        job.perform
      end
    end

    context "with corrected expenses (was_corrected: true)" do
      let!(:expense) do
        create(:expense, merchant_name: "Best Buy", category: category)
      end

      let!(:metric) do
        create(:categorization_metric,
          expense: expense,
          category: category,
          was_corrected: true,
          created_at: 25.hours.ago)
      end

      it "skips corrected expenses" do
        expect(updater_double).not_to receive(:upsert)
        job.perform
      end
    end

    context "when a corresponding vector already exists" do
      let!(:expense) do
        create(:expense, merchant_name: "Costco", category: category)
      end

      let!(:metric) do
        create(:categorization_metric,
          expense: expense,
          category: category,
          was_corrected: false,
          created_at: 25.hours.ago)
      end

      let!(:existing_vector) do
        create(:categorization_vector,
          merchant_normalized: Services::Categorization::MerchantNormalizer.normalize("Costco"),
          category: category)
      end

      it "skips expenses that already have a matching vector" do
        expect(updater_double).not_to receive(:upsert)
        job.perform
      end
    end

    context "when a single expense raises an error" do
      let!(:good_expense) do
        create(:expense, merchant_name: "Trader Joe's", category: category, description: "organic food")
      end

      let!(:bad_expense) do
        create(:expense, merchant_name: "Broken Store", category: other_category, description: "stuff")
      end

      let!(:good_metric) do
        create(:categorization_metric,
          expense: good_expense,
          category: category,
          was_corrected: false,
          created_at: 25.hours.ago)
      end

      let!(:bad_metric) do
        create(:categorization_metric,
          expense: bad_expense,
          category: other_category,
          was_corrected: false,
          created_at: 25.hours.ago)
      end

      before do
        allow(updater_double).to receive(:upsert) do |args|
          if args[:merchant] == "Broken Store"
            raise StandardError, "DB exploded"
          end
        end
      end

      it "continues processing other expenses after an error" do
        expect(updater_double).to receive(:upsert)
          .with(hash_including(merchant: "Trader Joe's"))

        job.perform
      end

      it "logs a warning for the failed expense" do
        expect(Rails.logger).to receive(:warn).with(/Broken Store.*DB exploded/)
        job.perform
      end

      it "does not raise the error" do
        expect { job.perform }.not_to raise_error
      end
    end

    context "idempotency" do
      let!(:expense) do
        create(:expense, merchant_name: "Amazon", category: category, description: "electronics")
      end

      let!(:metric) do
        create(:categorization_metric,
          expense: expense,
          category: category,
          was_corrected: false,
          created_at: 25.hours.ago)
      end

      it "processes the same expense only once across multiple runs" do
        # First run: no vector exists, so it processes and we create the vector in the callback
        first_run_count = 0
        allow(updater_double).to receive(:upsert) do |args|
          first_run_count += 1
          create(:categorization_vector,
            merchant_normalized: Services::Categorization::MerchantNormalizer.normalize(args[:merchant]),
            category: args[:category])
        end

        job.perform
        expect(first_run_count).to eq(1)

        # Second run: vector now exists, so it should skip
        second_run_count = 0
        second_updater = instance_double(Services::Categorization::Learning::VectorUpdater)
        allow(Services::Categorization::Learning::VectorUpdater)
          .to receive(:new).and_return(second_updater)
        allow(second_updater).to receive(:upsert) { second_run_count += 1 }

        described_class.new.perform
        expect(second_run_count).to eq(0)
      end
    end

    context "with expense missing merchant_name" do
      let!(:expense) do
        create(:expense, merchant_name: nil, category: category)
      end

      let!(:metric) do
        create(:categorization_metric,
          expense: expense,
          category: category,
          was_corrected: false,
          created_at: 25.hours.ago)
      end

      it "skips expenses without a merchant name" do
        expect(updater_double).not_to receive(:upsert)
        job.perform
      end
    end

    context "with expense missing category" do
      let!(:expense) do
        create(:expense, merchant_name: "Some Store", category: nil)
      end

      let!(:metric) do
        create(:categorization_metric,
          expense: expense,
          category: nil,
          was_corrected: false,
          created_at: 25.hours.ago)
      end

      it "skips expenses without a category" do
        expect(updater_double).not_to receive(:upsert)
        job.perform
      end
    end
  end

  describe "job configuration", unit: true do
    it "is queued on the low queue" do
      expect(described_class.queue_name).to eq("low")
    end
  end
end

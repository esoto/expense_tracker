# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExternalBudgets::PullJob, :unit do
  let(:source) { create(:external_budget_source) }
  let(:sync_service) { instance_double(Services::ExternalBudgets::SyncService) }

  describe "#perform" do
    context "with a valid active source" do
      it "invokes SyncService#call once" do
        allow(Services::ExternalBudgets::SyncService).to receive(:new).with(source: source).and_return(sync_service)
        expect(sync_service).to receive(:call).once.and_return(true)

        described_class.new.perform(source.id)
      end
    end

    context "when the source does not exist" do
      it "returns early without calling SyncService" do
        expect(Services::ExternalBudgets::SyncService).not_to receive(:new)
        expect { described_class.new.perform(-1) }.not_to raise_error
      end
    end

    context "when the source is inactive" do
      before { source.update!(active: false) }

      it "returns early without calling SyncService" do
        expect(Services::ExternalBudgets::SyncService).not_to receive(:new)
        described_class.new.perform(source.id)
      end
    end

    context "when SyncService raises UnauthorizedError internally" do
      # SyncService catches UnauthorizedError and returns false; the job
      # layer never sees it, so it must not retry.
      it "does not re-raise and does not retry at the job layer" do
        allow(Services::ExternalBudgets::SyncService).to receive(:new).with(source: source).and_return(sync_service)
        allow(sync_service).to receive(:call).and_return(false)

        expect { described_class.new.perform(source.id) }.not_to raise_error
      end
    end
  end

  describe "retry configuration" do
    let(:source_file) { Rails.root.join("app/jobs/external_budgets/pull_job.rb") }
    let(:source_text) { File.read(source_file) }

    it "retries on ApiClient::NetworkError with polynomially_longer backoff, attempts: 3" do
      expect(source_text).to match(/retry_on[^\n]*NetworkError[\s\S]{0,120}polynomially_longer[\s\S]{0,120}attempts:\s*3/)
    end

    it "retries on ApiClient::ServerError with polynomially_longer backoff, attempts: 3" do
      expect(source_text).to match(/retry_on[^\n]*ServerError[\s\S]{0,120}polynomially_longer[\s\S]{0,120}attempts:\s*3/)
    end
  end
end

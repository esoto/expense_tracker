# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataQualityAuditJob, type: :job, unit: true do
  let(:job) { described_class.new }

  let(:audit_result) do
    {
      timestamp: Time.current.iso8601,
      summary: {
        total_patterns: 10,
        active_patterns: 8,
        category_coverage: "75.0%",
        avg_success_rate: "80.0%",
        quality_grade: "B",
        quality_score: 0.85,
        critical_issues: 0,
        total_recommendations: 2
      },
      quality_score: { grade: "B", overall: 0.85 },
      recommendations: [ { type: :low_coverage, severity: :high } ]
    }
  end

  let(:checker_double) do
    instance_double(Services::Categorization::Monitoring::DataQualityChecker, audit: audit_result)
  end

  before do
    allow(Services::Categorization::Monitoring::DataQualityChecker)
      .to receive(:new).and_return(checker_double)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe "#perform", unit: true do
    it "runs without error" do
      expect { job.perform }.not_to raise_error
    end

    it "invokes the DataQualityChecker audit" do
      expect(checker_double).to receive(:audit).and_return(audit_result)
      job.perform
    end

    it "caches the audit result under the expected key" do
      Rails.cache.delete(DataQualityAuditJob::CACHE_KEY)
      job.perform
      cached = Rails.cache.read(DataQualityAuditJob::CACHE_KEY)
      expect(cached).to eq(audit_result)
    end

    it "caches the result with a 24-hour expiry" do
      expect(Rails.cache).to receive(:write).with(
        DataQualityAuditJob::CACHE_KEY,
        audit_result,
        expires_in: 24.hours
      )
      job.perform
    end

    it "logs the quality grade" do
      expect(Rails.logger).to receive(:info).with(/grade=B/)
      job.perform
    end

    it "logs the quality score" do
      expect(Rails.logger).to receive(:info).with(/score=0\.85/)
      job.perform
    end

    it "logs the number of recommendations" do
      expect(Rails.logger).to receive(:info).with(/recommendations=1/)
      job.perform
    end

    context "when the checker raises an error" do
      before do
        allow(checker_double).to receive(:audit).and_raise(StandardError, "DB connection failed")
      end

      it "logs the error message" do
        expect(Rails.logger).to receive(:error).with(/DB connection failed/)
        expect { job.perform }.to raise_error(StandardError)
      end

      it "re-raises the error so ActiveJob retry logic can engage" do
        expect { job.perform }.to raise_error(StandardError, "DB connection failed")
      end
    end
  end

  describe "job configuration", unit: true do
    it "is queued on the low queue" do
      expect(described_class.queue_name).to eq("low")
    end
  end
end

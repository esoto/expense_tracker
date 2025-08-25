# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncMetric, type: :model, unit: true do
  # Use build_stubbed for true unit testing
  let(:sync_session) { build_stubbed(:sync_session, id: 1) }
  let(:email_account) { build_stubbed(:email_account, id: 1, bank_name: "BCR", email: "test@bcr.com") }
  let(:sync_metric) do
    build_stubbed(:sync_metric,
      id: 1,
      sync_session: sync_session,
      email_account: email_account,
      metric_type: "account_sync",
      started_at: 1.hour.ago,
      completed_at: 30.minutes.ago,
      duration: 1800000, # 30 minutes in milliseconds
      success: true,
      emails_processed: 50,
      error_type: nil,
      error_message: nil,
      metadata: { "details" => "test" })
  end

  describe "constants" do
    it "defines METRIC_TYPES" do
      expect(described_class::METRIC_TYPES).to eq({
        session_overall: "session_overall",
        account_sync: "account_sync",
        email_fetch: "email_fetch",
        email_parse: "email_parse",
        expense_detection: "expense_detection",
        conflict_detection: "conflict_detection",
        database_write: "database_write",
        broadcast: "broadcast"
      })
    end

    it "freezes METRIC_TYPES" do
      expect(described_class::METRIC_TYPES).to be_frozen
    end
  end

  describe "validations" do
    subject { build(:sync_metric, sync_session: sync_session) }

    describe "metric_type validation" do
      it "validates presence of metric_type" do
        subject.metric_type = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:metric_type]).to include("can't be blank")
      end

      it "validates inclusion of metric_type" do
        subject.metric_type = "invalid_type"
        expect(subject).not_to be_valid
        expect(subject.errors[:metric_type]).to include("is not included in the list")
      end

      it "accepts valid metric types" do
        described_class::METRIC_TYPES.values.each do |type|
          subject.metric_type = type
          expect(subject).to be_valid
        end
      end
    end

    describe "started_at validation" do
      it "validates presence of started_at" do
        subject.started_at = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:started_at]).to include("can't be blank")
      end

      it "accepts valid timestamps" do
        subject.started_at = Time.current
        expect(subject).to be_valid
      end
    end

    describe "duration validation" do
      it "validates duration is non-negative" do
        subject.duration = -100
        expect(subject).not_to be_valid
        expect(subject.errors[:duration]).to include("must be greater than or equal to 0")
      end

      it "allows nil duration" do
        subject.duration = nil
        expect(subject).to be_valid
      end

      it "accepts zero duration" do
        subject.duration = 0
        expect(subject).to be_valid
      end

      it "accepts positive duration" do
        subject.duration = 1000
        expect(subject).to be_valid
      end
    end

    describe "emails_processed validation" do
      it "validates emails_processed is non-negative" do
        subject.emails_processed = -1
        expect(subject).not_to be_valid
        expect(subject.errors[:emails_processed]).to include("must be greater than or equal to 0")
      end

      it "accepts zero emails_processed" do
        subject.emails_processed = 0
        expect(subject).to be_valid
      end

      it "accepts positive emails_processed" do
        subject.emails_processed = 100
        expect(subject).to be_valid
      end
    end
  end

  describe "associations" do
    it "belongs to sync_session" do
      association = described_class.reflect_on_association(:sync_session)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be_falsey
    end

    it "belongs to email_account (optional)" do
      association = described_class.reflect_on_association(:email_account)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be true
    end
  end

  describe "callbacks" do
    describe "before_save :calculate_duration" do



      it "handles nil started_at" do
        metric = build(:sync_metric,
          sync_session: sync_session,
          started_at: nil,
          completed_at: Time.current,
          duration: nil)
        
        expect(metric).not_to be_valid # started_at is required
      end
    end
  end

  describe "scopes" do
    describe ".successful" do
      it "returns metrics with success true" do
        query = described_class.successful
        expect(query.to_sql).to include('"sync_metrics"."success" = TRUE')
      end
    end

    describe ".failed" do
      it "returns metrics with success false" do
        query = described_class.failed
        expect(query.to_sql).to include('"sync_metrics"."success" = FALSE')
      end
    end

    describe ".by_type" do
      it "filters by metric type" do
        query = described_class.by_type("account_sync")
        expect(query.to_sql).to include('"sync_metrics"."metric_type" = \'account_sync\'')
      end
    end

    describe ".recent" do
      it "orders by started_at descending" do
        query = described_class.recent
        expect(query.to_sql).to include("ORDER BY")
        expect(query.to_sql).to include("started_at")
        expect(query.to_sql).to include("DESC")
      end
    end

    describe ".in_period" do
      it "filters by date range" do
        start_date = 1.week.ago
        end_date = Time.current
        query = described_class.in_period(start_date, end_date)
        expect(query.to_sql).to include("started_at")
      end
    end

    describe ".for_session" do
      it "filters by sync_session_id" do
        query = described_class.for_session(5)
        expect(query.to_sql).to include('"sync_metrics"."sync_session_id" = 5')
      end
    end

    describe ".for_account" do
      it "filters by email_account_id" do
        query = described_class.for_account(3)
        expect(query.to_sql).to include('"sync_metrics"."email_account_id" = 3')
      end
    end

    describe ".last_24_hours" do
      it "returns metrics from last 24 hours" do
        freeze_time do
          query = described_class.last_24_hours
          expect(query.to_sql).to include("started_at")
        end
      end
    end

    describe ".last_7_days" do
      it "returns metrics from last 7 days" do
        freeze_time do
          query = described_class.last_7_days
          expect(query.to_sql).to include("started_at")
        end
      end
    end

    describe ".last_30_days" do
      it "returns metrics from last 30 days" do
        freeze_time do
          query = described_class.last_30_days
          expect(query.to_sql).to include("started_at")
        end
      end
    end
  end

  describe "class methods" do
    describe ".average_duration_by_type" do
      it "calculates average duration grouped by type" do
        relation = double("relation")
        grouped = double("grouped")
        averaged = double("averaged")
        
        expect(described_class).to receive(:last_24_hours).and_return(relation)
        expect(relation).to receive(:group).with(:metric_type).and_return(grouped)
        expect(grouped).to receive(:average).with(:duration).and_return(averaged)
        expect(averaged).to receive(:transform_values).and_return({
          "account_sync" => 1500.123
        })
        
        result = described_class.average_duration_by_type
        expect(result).to eq({ "account_sync" => 1500.123 })
      end

      it "accepts different periods" do
        relation = double("relation")
        expect(described_class).to receive(:last_7_days).and_return(relation)
        allow(relation).to receive_message_chain(:group, :average, :transform_values).and_return({})
        
        described_class.average_duration_by_type(:last_7_days)
      end

      it "rounds values to 3 decimal places" do
        allow(described_class).to receive_message_chain(:last_24_hours, :group, :average)
          .and_return({ "account_sync" => 1234.56789 })
        
        result = described_class.average_duration_by_type
        expect(result["account_sync"]).to eq(1234.568)
      end
    end

    describe ".success_rate_by_type" do
      it "calculates success rate for each metric type" do
        metrics_count = {
          ["account_sync", true] => 80,
          ["account_sync", false] => 20,
          ["email_fetch", true] => 95,
          ["email_fetch", false] => 5
        }
        
        allow(described_class).to receive_message_chain(:last_24_hours, :group, :count)
          .and_return(metrics_count)
        
        result = described_class.success_rate_by_type
        
        expect(result["account_sync"]).to eq(80.0)
        expect(result["email_fetch"]).to eq(95.0)
      end

      it "handles zero counts" do
        allow(described_class).to receive_message_chain(:last_24_hours, :group, :count)
          .and_return({})
        
        result = described_class.success_rate_by_type
        
        described_class::METRIC_TYPES.values.each do |type|
          expect(result[type]).to eq(0.0)
        end
      end

      it "rounds to 2 decimal places" do
        metrics_count = {
          ["account_sync", true] => 1,
          ["account_sync", false] => 2
        }
        
        allow(described_class).to receive_message_chain(:last_24_hours, :group, :count)
          .and_return(metrics_count)
        
        result = described_class.success_rate_by_type
        expect(result["account_sync"]).to eq(33.33)
      end
    end


    describe ".hourly_performance" do
      it "groups metrics by hour" do
        expect(described_class).to receive_message_chain(
          :where, :group_by_hour, :group, :count
        ).and_return({})
        
        described_class.hourly_performance
      end

      it "filters by metric type when provided" do
        query = double("query")
        expect(described_class).to receive(:where).and_return(query)
        expect(query).to receive(:by_type).with("account_sync").and_return(query)
        expect(query).to receive_message_chain(:group_by_hour, :group, :count)
        
        described_class.hourly_performance("account_sync")
      end

    end

    describe ".peak_hours" do
      it "returns top 5 peak hours" do
        hourly_counts = {
          "9 am" => 100,
          "10 am" => 150,
          "11 am" => 120,
          "2 pm" => 200,
          "3 pm" => 180,
          "4 pm" => 90,
          "5 pm" => 110
        }
        
        allow(described_class).to receive_message_chain(
          :last_7_days, :group_by_hour_of_day, :count
        ).and_return(hourly_counts)
        
        result = described_class.peak_hours
        
        expect(result.size).to eq(5)
        expect(result.keys.first).to eq("2 pm")
        expect(result.values.first).to eq(200)
      end

      it "accepts different periods" do
        expect(described_class).to receive(:last_30_days).and_call_original
        allow(described_class).to receive_message_chain(
          :last_30_days, :group_by_hour_of_day, :count
        ).and_return({})
        
        described_class.peak_hours(:last_30_days)
      end
    end

    describe ".account_performance_summary" do
      let(:account1) { build_stubbed(:email_account, id: 1, bank_name: "BCR", email: "test1@bcr.com") }
      let(:account2) { build_stubbed(:email_account, id: 2, bank_name: "BAC", email: "test2@bac.com") }

      before do
        allow(EmailAccount).to receive_message_chain(:active, :includes).and_return([account1, account2])
        allow(described_class).to receive_message_chain(:last_24_hours, :includes, :by_type, :group_by)
          .and_return({})
        allow(described_class).to receive_message_chain(:last_24_hours, :group, :sum)
          .and_return({ 1 => 100, 2 => 150 })
        allow(described_class).to receive_message_chain(:last_24_hours, :by_type, :group, :count)
          .and_return({ 1 => 10, 2 => 15 })
        allow(described_class).to receive_message_chain(:last_24_hours, :by_type, :group, :average)
          .and_return({ 1 => 5000.0, 2 => 7500.0 })
        allow(described_class).to receive_message_chain(:last_24_hours, :by_type, :successful, :group, :count)
          .and_return({ 1 => 8, 2 => 14 })
      end

      it "returns performance summary for each account" do
        result = described_class.account_performance_summary
        
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        
        first_account = result.first
        expect(first_account[:account_id]).to eq(1)
        expect(first_account[:bank_name]).to eq("BCR")
        expect(first_account[:email]).to eq("test1@bcr.com")
        expect(first_account[:total_syncs]).to eq(10)
        expect(first_account[:average_duration]).to eq(5000.0)
        expect(first_account[:success_rate]).to eq(80.0)
        expect(first_account[:emails_processed]).to eq(100)
      end

      it "handles accounts with no metrics" do
        allow(described_class).to receive_message_chain(:last_24_hours, :by_type, :group, :count)
          .and_return({})
        allow(described_class).to receive_message_chain(:last_24_hours, :group, :sum)
          .and_return({})
        
        result = described_class.account_performance_summary
        
        first_account = result.first
        expect(first_account[:total_syncs]).to eq(0)
        expect(first_account[:success_rate]).to eq(0.0)
        expect(first_account[:emails_processed]).to eq(0)
      end

      it "accepts different periods" do
        expect(described_class).to receive(:last_7_days).at_least(:once).and_call_original
        allow(described_class).to receive_message_chain(:last_7_days, :includes, :by_type, :group_by)
          .and_return({})
        allow(described_class).to receive_message_chain(:last_7_days, :group, :sum).and_return({})
        allow(described_class).to receive_message_chain(:last_7_days, :by_type, :group, :count).and_return({})
        allow(described_class).to receive_message_chain(:last_7_days, :by_type, :group, :average).and_return({})
        allow(described_class).to receive_message_chain(:last_7_days, :by_type, :successful, :group, :count).and_return({})
        
        described_class.account_performance_summary(:last_7_days)
      end
    end

    describe ".calculate_success_rate (private)" do
      it "calculates success rate correctly" do
        scope = double("scope")
        allow(scope).to receive(:count).and_return(100)
        allow(scope).to receive_message_chain(:successful, :count).and_return(85)
        
        result = described_class.send(:calculate_success_rate, scope)
        expect(result).to eq(85.0)
      end

      it "handles zero total" do
        scope = double("scope")
        allow(scope).to receive(:count).and_return(0)
        
        result = described_class.send(:calculate_success_rate, scope)
        expect(result).to eq(0.0)
      end

      it "rounds to 2 decimal places" do
        scope = double("scope")
        allow(scope).to receive(:count).and_return(3)
        allow(scope).to receive_message_chain(:successful, :count).and_return(2)
        
        result = described_class.send(:calculate_success_rate, scope)
        expect(result).to eq(66.67)
      end
    end
  end

  describe "instance methods" do
    describe "#duration_in_seconds" do
      it "converts milliseconds to seconds" do
        sync_metric.duration = 1500
        expect(sync_metric.duration_in_seconds).to eq(1.5)
      end

      it "rounds to 3 decimal places" do
        sync_metric.duration = 1234
        expect(sync_metric.duration_in_seconds).to eq(1.234)
      end

      it "returns nil for nil duration" do
        sync_metric.duration = nil
        expect(sync_metric.duration_in_seconds).to be_nil
      end

      it "handles zero duration" do
        sync_metric.duration = 0
        expect(sync_metric.duration_in_seconds).to eq(0.0)
      end
    end

    describe "#processing_rate" do
      it "calculates emails per second" do
        sync_metric.duration = 10000 # 10 seconds
        sync_metric.emails_processed = 50
        
        expect(sync_metric.processing_rate).to eq(5.0)
      end

      it "rounds to 2 decimal places" do
        sync_metric.duration = 3000 # 3 seconds
        sync_metric.emails_processed = 10
        
        expect(sync_metric.processing_rate).to eq(3.33)
      end

      it "returns nil for nil duration" do
        sync_metric.duration = nil
        expect(sync_metric.processing_rate).to be_nil
      end

      it "returns nil for zero duration" do
        sync_metric.duration = 0
        expect(sync_metric.processing_rate).to be_nil
      end

      it "returns nil for zero emails processed" do
        sync_metric.emails_processed = 0
        expect(sync_metric.processing_rate).to be_nil
      end
    end

    describe "#status_badge" do
      it "returns 'success' for successful metrics" do
        sync_metric.success = true
        expect(sync_metric.status_badge).to eq("success")
      end

      it "returns 'error' for failed metrics" do
        sync_metric.success = false
        expect(sync_metric.status_badge).to eq("error")
      end
    end
  end

  describe "edge cases and error conditions" do
    describe "duration calculation edge cases" do
      it "handles very small durations" do
        sync_metric.duration = 1 # 1 millisecond
        expect(sync_metric.duration_in_seconds).to eq(0.001)
      end

      it "handles very large durations" do
        sync_metric.duration = 86400000 # 24 hours in milliseconds
        expect(sync_metric.duration_in_seconds).to eq(86400.0)
      end

      it "handles negative duration in validation" do
        sync_metric.duration = -1000
        expect(sync_metric).not_to be_valid
      end
    end

    describe "processing rate edge cases" do
      it "handles very high processing rates" do
        sync_metric.duration = 1 # 1 millisecond
        sync_metric.emails_processed = 1000
        
        expect(sync_metric.processing_rate).to eq(1000000.0)
      end

      it "handles fractional processing rates" do
        sync_metric.duration = 10000 # 10 seconds
        sync_metric.emails_processed = 1
        
        expect(sync_metric.processing_rate).to eq(0.1)
      end
    end

    describe "timestamp edge cases" do
      it "handles future timestamps" do
        metric = build(:sync_metric,
          sync_session: sync_session,
          started_at: 1.hour.from_now,
          completed_at: 2.hours.from_now)
        
        expect(metric).to be_valid
      end

      it "handles very old timestamps" do
        metric = build(:sync_metric,
          sync_session: sync_session,
          started_at: 100.years.ago)
        
        expect(metric).to be_valid
      end

    end
  end

  describe "performance considerations" do
    describe "query optimization" do
      it "uses indexed columns in scopes" do
        expect(described_class.by_type("account_sync").to_sql).to include("metric_type")
        expect(described_class.for_session(1).to_sql).to include("sync_session_id")
        expect(described_class.for_account(1).to_sql).to include("email_account_id")
      end

    end

    describe "aggregation optimization" do
      it "uses database aggregation functions" do
        # average_duration_by_type uses database AVG
        expect(described_class).to receive_message_chain(:last_24_hours, :group, :average)
        allow(described_class).to receive_message_chain(:last_24_hours, :group, :average, :transform_values).and_return({})
        
        described_class.average_duration_by_type
      end

    end
  end

  describe "security considerations" do
    describe "input validation" do
      it "validates metric_type against whitelist" do
        sync_metric.metric_type = "'; DROP TABLE sync_metrics; --"
        expect(sync_metric).not_to be_valid
        expect(sync_metric.errors[:metric_type]).to include("is not included in the list")
      end

      it "handles malicious error messages safely" do
        sync_metric.error_message = "<script>alert('XSS')</script>"
        expect(sync_metric).to be_valid
        expect(sync_metric.error_message).to eq("<script>alert('XSS')</script>")
      end
    end

    describe "data isolation" do
      it "scopes metrics to sync_session" do
        expect(sync_metric.sync_session).to eq(sync_session)
        expect(sync_metric.sync_session_id).to eq(sync_session.id)
      end

      it "optionally scopes to email_account" do
        sync_metric.email_account = nil
        expect(sync_metric).to be_valid
      end
    end
  end

  describe "business logic" do
    describe "metric type usage" do
      it "supports session-level metrics without account" do
        sync_metric.metric_type = "session_overall"
        sync_metric.email_account = nil
        expect(sync_metric).to be_valid
      end

      it "supports account-specific metrics" do
        sync_metric.metric_type = "account_sync"
        sync_metric.email_account = email_account
        expect(sync_metric).to be_valid
      end
    end

    describe "success tracking" do
      it "tracks successful operations" do
        sync_metric.success = true
        sync_metric.error_type = nil
        sync_metric.error_message = nil
        expect(sync_metric).to be_valid
      end

      it "tracks failed operations with error details" do
        sync_metric.success = false
        sync_metric.error_type = "ConnectionError"
        sync_metric.error_message = "Failed to connect to server"
        expect(sync_metric).to be_valid
      end
    end

    describe "metadata storage" do
      it "stores arbitrary metadata" do
        sync_metric.metadata = {
          "retries" => 3,
          "server" => "imap.gmail.com",
          "ssl" => true
        }
        expect(sync_metric).to be_valid
      end

      it "handles nil metadata" do
        sync_metric.metadata = nil
        expect(sync_metric).to be_valid
      end
    end
  end
end
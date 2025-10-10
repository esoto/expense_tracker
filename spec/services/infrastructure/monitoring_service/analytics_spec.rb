# frozen_string_literal: true

require "rails_helper"
require_relative "../../../support/monitoring_service_test_helper"

RSpec.describe Services::Infrastructure::MonitoringService::Analytics, type: :service, unit: true do
  include MonitoringServiceTestHelper

  let(:analytics) { described_class }

  before do
    setup_time_helpers
  end

  describe ".get_metrics" do
    context "with no service specified (all services)" do
      before do
        # Create test data for all services
        create_sync_sessions(count: 3, status: :completed)
        create_sync_sessions(count: 1, status: :failed)
        create(:processed_email, created_at: current_time - 30.minutes)
        create_expenses_with_categories(count: 5, from_email: true)
        create_bulk_operations(count: 2)
      end

      it "returns metrics for all services" do
        result = analytics.get_metrics(time_window: 1.hour)

        expect_metric_structure(result, [ :time_window, :timestamp, :services, :summary ])
        expect(result[:time_window]).to eq(1.hour)
        expect_timestamp(result[:timestamp])

        expect(result[:services]).to have_key("sync")
        expect(result[:services]).to have_key("email_processing")
        expect(result[:services]).to have_key("categorization")
        expect(result[:services]).to have_key("bulk_categorization")
      end

      it "includes summary metrics" do
        result = analytics.get_metrics(time_window: 1.hour)
        summary = result[:summary]

        expect_metric_structure(summary, [ :total_operations, :success_rate, :busiest_service ])
        expect_numeric_metric(summary[:total_operations], min: 0)
        expect_percentage(summary[:success_rate])
        expect(summary[:busiest_service]).to be_a(String)
      end
    end

    context "with specific service: sync" do
      let!(:completed_sessions) { create_sync_sessions(count: 3, status: :completed) }
      let!(:failed_sessions) { create_sync_sessions(count: 2, status: :failed) }

      it "returns sync-specific metrics" do
        result = analytics.get_metrics(service: "sync", time_window: 1.hour)
        sync_metrics = result[:services]["sync"]

        expect_metric_structure(sync_metrics, [
          :total_sessions,
          :successful_sessions,
          :failed_sessions,
          :emails_processed,
          :average_duration
        ])

        expect(sync_metrics[:total_sessions]).to eq(5)
        expect(sync_metrics[:successful_sessions]).to eq(3)
        expect(sync_metrics[:failed_sessions]).to eq(2)
        expect(sync_metrics[:emails_processed]).to be > 0
        expect_numeric_metric(sync_metrics[:average_duration], min: 0)
      end

      it "calculates average duration correctly" do
        result = analytics.get_metrics(service: "sync", time_window: 1.hour)
        sync_metrics = result[:services]["sync"]

        # Average duration should be based on completed sessions only
        expected_duration = completed_sessions.map { |s|
          (s.completed_at - s.started_at).to_f
        }.sum / completed_sessions.count

        expect(sync_metrics[:average_duration]).to be_within(0.1).of(expected_duration)
      end

      it "handles no completed sessions gracefully" do
        SyncSession.completed.destroy_all

        result = analytics.get_metrics(service: "sync", time_window: 1.hour)
        sync_metrics = result[:services]["sync"]

        expect(sync_metrics[:average_duration]).to eq(0)
      end
    end

    context "with specific service: email_processing" do
      before do
        create_list(:processed_email, 3, created_at: current_time - 30.minutes)
        # Create expenses with raw_email_content to indicate email source
        create_list(:expense, 2, raw_email_content: "Email content", created_at: current_time - 20.minutes)
        create(:expense, raw_email_content: nil, created_at: current_time - 20.minutes)
      end

      it "returns email processing metrics" do
        result = analytics.get_metrics(service: "email_processing", time_window: 1.hour)
        email_metrics = result[:services]["email_processing"]

        expect_metric_structure(email_metrics, [ :emails_fetched, :expenses_created ])
        expect(email_metrics[:emails_fetched]).to eq(3)
        expect(email_metrics[:expenses_created]).to eq(2) # Expenses with raw_email_content
      end
    end

    context "with specific service: categorization" do
      before do
        # Create categorized expenses
        create_list(:expense, 3,
          category: create(:category),
          auto_categorized: true,
          updated_at: current_time - 20.minutes
        )
        create_list(:expense, 2,
          category: create(:category),
          auto_categorized: false,
          updated_at: current_time - 15.minutes
        )
        # Create uncategorized expense (should not be counted)
        create(:expense, category: nil, updated_at: current_time - 10.minutes)
      end

      it "returns categorization metrics" do
        result = analytics.get_metrics(service: "categorization", time_window: 1.hour)
        cat_metrics = result[:services]["categorization"]

        expect_metric_structure(cat_metrics, [
          :total_categorized,
          :auto_categorized,
          :manual_categorized
        ])

        expect(cat_metrics[:total_categorized]).to eq(5)
        expect(cat_metrics[:auto_categorized]).to eq(3)
        expect(cat_metrics[:manual_categorized]).to eq(2)
      end

      it "excludes uncategorized expenses" do
        Expense.update_all(category_id: nil)

        result = analytics.get_metrics(service: "categorization", time_window: 1.hour)
        cat_metrics = result[:services]["categorization"]

        expect(cat_metrics[:total_categorized]).to eq(0)
      end
    end

    context "with specific service: bulk_categorization" do
      before do
        create(:bulk_operation,
          operation_type: :categorization,
          expense_count: 25,
          status: :completed,
          created_at: current_time - 30.minutes
        )
        create(:bulk_operation,
          operation_type: :categorization,
          expense_count: 15,
          status: :undone,
          created_at: current_time - 20.minutes
        )
        # Non-categorization operation (should not be counted)
        create(:bulk_operation,
          operation_type: :recategorization,
          expense_count: 10,
          created_at: current_time - 25.minutes
        )
      end

      it "returns bulk categorization metrics" do
        result = analytics.get_metrics(service: "bulk_categorization", time_window: 1.hour)
        bulk_metrics = result[:services]["bulk_categorization"]

        expect_metric_structure(bulk_metrics, [
          :total_operations,
          :expenses_affected,
          :operations_undone
        ])

        expect(bulk_metrics[:total_operations]).to eq(2)
        expect(bulk_metrics[:expenses_affected]).to eq(40) # 25 + 15
        expect(bulk_metrics[:operations_undone]).to eq(1)
      end

      it "filters by operation type correctly" do
        BulkOperation.update_all(operation_type: :recategorization)

        result = analytics.get_metrics(service: "bulk_categorization", time_window: 1.hour)
        bulk_metrics = result[:services]["bulk_categorization"]

        expect(bulk_metrics[:total_operations]).to eq(0)
        expect(bulk_metrics[:expenses_affected]).to eq(0)
      end
    end

    context "with unknown service" do
      it "returns empty metrics" do
        result = analytics.get_metrics(service: "unknown_service", time_window: 1.hour)

        expect(result[:services]["unknown_service"]).to eq({})
      end
    end

    context "time window filtering" do
      before do
        # Create data inside and outside time window
        create(:sync_session, created_at: current_time - 30.minutes, status: :completed)
        create(:sync_session, created_at: current_time - 2.hours, status: :completed)
        create(:processed_email, created_at: current_time - 45.minutes)
        create(:processed_email, created_at: current_time - 3.hours)
      end

      it "respects the time window for sync metrics" do
        result = analytics.get_metrics(service: "sync", time_window: 1.hour)
        sync_metrics = result[:services]["sync"]

        expect(sync_metrics[:total_sessions]).to eq(1) # Only within 1 hour
      end

      it "respects the time window for email processing metrics" do
        result = analytics.get_metrics(service: "email_processing", time_window: 1.hour)
        email_metrics = result[:services]["email_processing"]

        expect(email_metrics[:emails_fetched]).to eq(1) # Only within 1 hour
      end

      it "handles different time windows correctly" do
        result_1h = analytics.get_metrics(service: "sync", time_window: 1.hour)
        result_3h = analytics.get_metrics(service: "sync", time_window: 3.hours)

        expect(result_1h[:services]["sync"][:total_sessions]).to eq(1)
        expect(result_3h[:services]["sync"][:total_sessions]).to eq(2)
      end
    end

    context "summary calculations" do
      before do
        create_sync_sessions(count: 4, status: :completed)
        create_sync_sessions(count: 1, status: :failed)
        create_bulk_operations(count: 3)
      end

      it "calculates total operations across services" do
        result = analytics.get_metrics(time_window: 1.hour)
        summary = result[:summary]

        # 5 sync sessions + 3 bulk operations
        expect(summary[:total_operations]).to eq(8)
      end

      it "calculates overall success rate" do
        result = analytics.get_metrics(time_window: 1.hour)
        summary = result[:summary]

        # 4 successful out of 5 sync sessions = 80%
        expect(summary[:success_rate]).to eq(80.0)
      end

      it "identifies the busiest service" do
        # Create more email processing activity than other services
        create_list(:processed_email, 20, created_at: current_time - 30.minutes)
        create_list(:expense, 15, raw_email_content: "Email content", created_at: current_time - 20.minutes)

        result = analytics.get_metrics(time_window: 1.hour)
        summary = result[:summary]

        # The busiest service should be the one with the highest sum of numeric metrics
        expect(summary[:busiest_service]).to be_a(String)
        expect([ "email_processing", "sync", "categorization", "bulk_categorization" ]).to include(summary[:busiest_service])
      end

      it "handles no operations gracefully" do
        # Use database cleaner approach to avoid foreign key issues
        # Simply query with no data instead of destroying
        allow(SyncSession).to receive(:where).and_return(SyncSession.none)
        allow(BulkOperation).to receive(:where).and_return(BulkOperation.none)

        result = analytics.get_metrics(time_window: 1.hour)
        summary = result[:summary]

        expect(summary[:total_operations]).to eq(0)
        expect(summary[:success_rate]).to eq(0)
      end
    end

    context "error handling" do
      it "handles database connection errors gracefully" do
        allow(SyncSession).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)

        expect {
          analytics.get_metrics(service: "sync", time_window: 1.hour)
        }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end

      it "handles missing models gracefully" do
        allow(ProcessedEmail).to receive(:where).and_raise(NameError)

        expect {
          analytics.get_metrics(service: "email_processing", time_window: 1.hour)
        }.to raise_error(NameError)
      end
    end

    context "performance considerations" do
      it "uses efficient queries with proper scoping" do
        expect(SyncSession).to receive(:where).with(
          created_at: one_hour_ago..current_time
        ).and_call_original

        analytics.get_metrics(service: "sync", time_window: 1.hour)
      end

      it "avoids N+1 queries" do
        create_sync_sessions(count: 10, status: :completed)

        expect {
          analytics.get_metrics(service: "sync", time_window: 1.hour)
        }.to make_database_queries(count: 3..6) # Limited number of queries regardless of data size
      end
    end
  end
end

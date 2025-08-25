# frozen_string_literal: true

require "rails_helper"

RSpec.describe FailedBroadcastStore, type: :model, unit: true do
  describe "constants" do
    it "defines ERROR_TYPES" do
      expect(FailedBroadcastStore::ERROR_TYPES).to eq(%w[
        record_not_found
        connection_timeout
        channel_error
        job_error
        job_death
        serialization_error
        validation_error
        unknown
      ])
    end

    it "defines PRIORITIES" do
      expect(FailedBroadcastStore::PRIORITIES).to eq(%w[critical high medium low])
    end
  end

  describe "callbacks" do
    describe "before_validation" do
      it "ensures data is present" do
        store = build_stubbed(:failed_broadcast_store, data: nil)
        store.send(:ensure_data_present)
        expect(store.data).to eq({})
      end

      it "preserves existing data" do
        existing_data = { "key" => "value" }
        store = build_stubbed(:failed_broadcast_store, data: existing_data)
        store.send(:ensure_data_present)
        expect(store.data).to eq(existing_data)
      end
    end
  end

  describe "validations" do
    it { should validate_presence_of(:channel_name) }
    it { should validate_presence_of(:target_type) }
    it { should validate_presence_of(:target_id) }
    it { should validate_numericality_of(:target_id).is_greater_than(0) }
    it { should validate_presence_of(:priority) }
    it { should validate_inclusion_of(:priority).in_array(FailedBroadcastStore::PRIORITIES) }
    it { should validate_presence_of(:error_type) }
    it { should validate_inclusion_of(:error_type).in_array(FailedBroadcastStore::ERROR_TYPES) }
    it { should validate_presence_of(:error_message) }
    it { should validate_presence_of(:failed_at) }
    it { should validate_presence_of(:retry_count) }
    it { should validate_numericality_of(:retry_count).is_greater_than_or_equal_to(0) }

    describe "sidekiq_job_id uniqueness" do
      it "validates uniqueness when present" do
        # Mock the validation to avoid database interaction in unit tests
        store = build_stubbed(:failed_broadcast_store, sidekiq_job_id: "unique_job_123")

        # Mock the uniqueness check to simulate no duplicate exists
        allow(FailedBroadcastStore).to receive(:exists?).with(sidekiq_job_id: "unique_job_123").and_return(false)

        expect(store).to be_valid
      end

      it "allows nil sidekiq_job_id" do
        store = build_stubbed(:failed_broadcast_store, sidekiq_job_id: nil)
        expect(store).to be_valid
      end
    end
  end

  describe "scopes" do
    describe ".unrecovered" do
      it "returns broadcasts not recovered" do
        # Test the scope by checking the SQL it generates
        scope_sql = FailedBroadcastStore.unrecovered.to_sql
        expect(scope_sql).to include('"recovered_at" IS NULL')
      end
    end

    describe ".recovered" do
      it "returns recovered broadcasts" do
        # Test the scope by checking the SQL it generates
        scope_sql = FailedBroadcastStore.recovered.to_sql
        expect(scope_sql).to include('"recovered_at" IS NOT NULL')
      end
    end

    describe ".by_priority" do
      it "filters by priority" do
        # Test the scope by checking the SQL it generates
        scope_sql = FailedBroadcastStore.by_priority("high").to_sql
        expect(scope_sql).to include('"priority" = \'high\'')
      end
    end

    describe ".by_channel" do
      it "filters by channel name" do
        # Test the scope by checking the SQL it generates
        scope_sql = FailedBroadcastStore.by_channel("ExpenseChannel").to_sql
        expect(scope_sql).to include('"channel_name" = \'ExpenseChannel\'')
      end
    end

    describe ".by_error_type" do
      it "filters by error type" do
        # Test the scope by checking the SQL it generates
        scope_sql = FailedBroadcastStore.by_error_type("connection_timeout").to_sql
        expect(scope_sql).to include('"error_type" = \'connection_timeout\'')
      end
    end

    describe ".recent_failures" do
      it "orders by failed_at descending" do
        # Test the scope by checking the SQL it generates
        scope_sql = FailedBroadcastStore.recent_failures.to_sql
        expect(scope_sql).to include('ORDER BY "failed_broadcast_stores"."failed_at" DESC')
      end
    end

    describe ".ready_for_retry" do
      it "returns unrecovered broadcasts below max retry attempts" do
        unrecovered = double("unrecovered_relation")
        final_relation = double("final_relation")

        expect(FailedBroadcastStore).to receive(:unrecovered).and_return(unrecovered)
        expect(FailedBroadcastStore).to receive(:max_retry_attempts).and_return(3)
        expect(unrecovered).to receive(:where).with("retry_count < ?", 3).and_return(final_relation)

        expect(FailedBroadcastStore.ready_for_retry).to eq(final_relation)
      end
    end
  end

  describe "class methods" do
    describe ".max_retry_attempts" do
      it "returns 5 for critical priority" do
        expect(FailedBroadcastStore.max_retry_attempts("critical")).to eq(5)
      end

      it "returns 4 for high priority" do
        expect(FailedBroadcastStore.max_retry_attempts("high")).to eq(4)
      end

      it "returns 3 for medium priority" do
        expect(FailedBroadcastStore.max_retry_attempts("medium")).to eq(3)
      end

      it "returns 2 for low priority" do
        expect(FailedBroadcastStore.max_retry_attempts("low")).to eq(2)
      end

      it "defaults to 3 for unknown priority" do
        expect(FailedBroadcastStore.max_retry_attempts("unknown")).to eq(3)
      end

      it "defaults to 3 when no priority provided" do
        expect(FailedBroadcastStore.max_retry_attempts).to eq(3)
      end
    end

    describe ".create_from_job_failure!" do
      it "creates record from job data and error" do
        job = {
          "args" => [ "ChannelName", 123, "Expense", { "data" => "value" }, "high" ],
          "retry_count" => 2,
          "jid" => "job_123"
        }
        error = ActiveRecord::RecordNotFound.new("Record not found")

        expect(FailedBroadcastStore).to receive(:classify_error).with(error).and_return("record_not_found")
        expect(Time).to receive(:current).and_return(Time.new(2024, 1, 1))

        expect(FailedBroadcastStore).to receive(:create!).with(
          channel_name: "ChannelName",
          target_type: "Expense",
          target_id: 123,
          data: { "data" => "value" },
          priority: "high",
          error_type: "record_not_found",
          error_message: "Record not found",
          failed_at: Time.new(2024, 1, 1),
          retry_count: 2,
          sidekiq_job_id: "job_123"
        )

        FailedBroadcastStore.create_from_job_failure!(job, error)
      end

      it "handles missing job args" do
        job = { "jid" => "job_123" }
        error = StandardError.new("Error")

        expect(FailedBroadcastStore).to receive(:classify_error).and_return("unknown")
        expect(Time).to receive(:current).and_return(Time.new(2024, 1, 1))

        expect(FailedBroadcastStore).to receive(:create!).with(hash_including(
          data: {},
          priority: "medium",
          retry_count: 0
        ))

        FailedBroadcastStore.create_from_job_failure!(job, error)
      end
    end

    describe ".classify_error" do
      it "classifies ActiveRecord::RecordNotFound" do
        error = ActiveRecord::RecordNotFound.new
        expect(FailedBroadcastStore.classify_error(error)).to eq("record_not_found")
      end

      it "classifies Timeout errors" do
        expect(FailedBroadcastStore.classify_error(Timeout::Error.new)).to eq("connection_timeout")
        expect(FailedBroadcastStore.classify_error(Net::ReadTimeout.new)).to eq("connection_timeout")
        expect(FailedBroadcastStore.classify_error(Net::OpenTimeout.new)).to eq("connection_timeout")
      end

      it "classifies JSON errors" do
        expect(FailedBroadcastStore.classify_error(JSON::ParserError.new("parse error"))).to eq("serialization_error")
        expect(FailedBroadcastStore.classify_error(JSON::GeneratorError.new("gen error"))).to eq("serialization_error")
      end

      it "classifies validation errors" do
        error = ActiveModel::ValidationError.new(build_stubbed(:expense))
        expect(FailedBroadcastStore.classify_error(error)).to eq("validation_error")
      end

      it "classifies unknown errors" do
        expect(FailedBroadcastStore.classify_error(StandardError.new)).to eq("unknown")
        expect(FailedBroadcastStore.classify_error(RuntimeError.new)).to eq("unknown")
      end
    end

    describe ".recovery_stats" do
      it "returns comprehensive statistics" do
        time_period = 24.hours
        start_time = Time.new(2024, 1, 1, 0, 0, 0)
        current_time = Time.new(2024, 1, 2, 0, 0, 0)

        allow(Time).to receive(:current).and_return(current_time)

        # Mock the 3 different queries based on actual implementation
        total_query = double("total_query")
        recovered_query = double("recovered_query")
        pending_query = double("pending_query")
        error_group_query = double("error_group_query")
        priority_group_query = double("priority_group_query")

        # Mock the where calls that actually happen in the implementation - there are 3 separate calls
        expect(FailedBroadcastStore).to receive(:where).with("failed_at >= ?", start_time).and_return(total_query).exactly(3).times

        # First call: total_failures count
        expect(total_query).to receive(:count).and_return(10).ordered

        # Second call: by_error_type grouping
        expect(total_query).to receive(:group).with(:error_type).and_return(error_group_query).ordered
        expect(error_group_query).to receive(:count).and_return({ "connection_timeout" => 5, "unknown" => 5 }).ordered

        # Third call: by_priority grouping
        expect(total_query).to receive(:group).with(:priority).and_return(priority_group_query).ordered
        expect(priority_group_query).to receive(:count).and_return({ "high" => 6, "medium" => 4 }).ordered

        # Separate queries for recovered and pending
        expect(FailedBroadcastStore).to receive(:where).with("failed_at >= ? AND recovered_at IS NOT NULL", start_time).and_return(recovered_query)
        expect(recovered_query).to receive(:count).and_return(3)

        expect(FailedBroadcastStore).to receive(:where).with("failed_at >= ? AND recovered_at IS NULL", start_time).and_return(pending_query)
        expect(pending_query).to receive(:count).and_return(7)

        stats = FailedBroadcastStore.recovery_stats(time_period: time_period)

        expect(stats).to eq({
          total_failures: 10,
          recovered: 3,
          pending_recovery: 7,
          by_error_type: { "connection_timeout" => 5, "unknown" => 5 },
          by_priority: { "high" => 6, "medium" => 4 }
        })
      end
    end

    describe ".cleanup_old_records" do
      it "deletes old recovered records" do
        older_than = 1.week
        cutoff_time = Time.new(2024, 1, 1)
        current_time = Time.new(2024, 1, 8)

        allow(Time).to receive(:current).and_return(current_time)

        recovered_scope = double("recovered_scope")
        old_records = double("old_records")

        expect(FailedBroadcastStore).to receive(:recovered).and_return(recovered_scope)
        expect(recovered_scope).to receive(:where).with("recovered_at < ?", cutoff_time).and_return(old_records)
        expect(old_records).to receive(:delete_all).and_return(5)

        result = FailedBroadcastStore.cleanup_old_records(older_than: older_than)
        expect(result).to eq(5)
      end
    end
  end

  describe "instance methods" do
    describe "#can_retry?" do
      context "when not recovered and below max retries" do
        it "returns true" do
          store = build_stubbed(:failed_broadcast_store,
            recovered_at: nil,
            retry_count: 2,
            priority: "medium"
          )
          allow(FailedBroadcastStore).to receive(:max_retry_attempts).with("medium").and_return(3)
          expect(store.can_retry?).to be true
        end
      end

      context "when recovered" do
        it "returns false" do
          store = build_stubbed(:failed_broadcast_store,
            recovered_at: Time.current,
            retry_count: 0,
            priority: "medium"
          )
          expect(store.can_retry?).to be false
        end
      end

      context "when at max retry attempts" do
        it "returns false" do
          store = build_stubbed(:failed_broadcast_store,
            recovered_at: nil,
            retry_count: 3,
            priority: "medium"
          )
          allow(FailedBroadcastStore).to receive(:max_retry_attempts).with("medium").and_return(3)
          expect(store.can_retry?).to be false
        end
      end
    end

    describe "#mark_recovered!" do
      it "updates recovery timestamp and notes" do
        store = build_stubbed(:failed_broadcast_store)
        current_time = Time.new(2024, 1, 1)
        allow(Time).to receive(:current).and_return(current_time)

        expect(store).to receive(:update!).with(
          recovered_at: current_time,
          recovery_notes: "Manual recovery"
        )

        store.mark_recovered!(notes: "Manual recovery")
      end

      it "works without notes" do
        store = build_stubbed(:failed_broadcast_store)
        current_time = Time.new(2024, 1, 1)
        allow(Time).to receive(:current).and_return(current_time)

        expect(store).to receive(:update!).with(
          recovered_at: current_time,
          recovery_notes: nil
        )

        store.mark_recovered!
      end
    end

    describe "#target_object" do
      it "finds the target object when it exists" do
        store = build_stubbed(:failed_broadcast_store, target_type: "Expense", target_id: 123)
        expense = double("expense")

        expect(Expense).to receive(:find).with(123).and_return(expense)
        expect(store.target_object).to eq(expense)
      end

      it "returns nil when target doesn't exist" do
        store = build_stubbed(:failed_broadcast_store, target_type: "Expense", target_id: 999)

        expect(Expense).to receive(:find).with(999).and_raise(ActiveRecord::RecordNotFound)
        expect(store.target_object).to be_nil
      end

      it "returns nil for invalid target type" do
        store = build_stubbed(:failed_broadcast_store, target_type: "InvalidModel", target_id: 123)

        expect { "InvalidModel".constantize }.to raise_error(NameError)
        expect(store.target_object).to be_nil
      end
    end

    describe "#target_exists?" do
      it "returns true when target exists" do
        store = build_stubbed(:failed_broadcast_store)
        allow(store).to receive(:target_object).and_return(double("object"))
        expect(store.target_exists?).to be true
      end

      it "returns false when target doesn't exist" do
        store = build_stubbed(:failed_broadcast_store)
        allow(store).to receive(:target_object).and_return(nil)
        expect(store.target_exists?).to be false
      end
    end

    describe "#error_description" do
      it "describes record_not_found errors" do
        store = build_stubbed(:failed_broadcast_store,
          error_type: "record_not_found",
          target_type: "Expense",
          target_id: 123
        )
        expect(store.error_description).to eq("Target object Expense#123 not found")
      end

      it "describes connection_timeout errors" do
        store = build_stubbed(:failed_broadcast_store, error_type: "connection_timeout")
        expect(store.error_description).to eq("Connection timeout while broadcasting")
      end

      it "describes serialization_error" do
        store = build_stubbed(:failed_broadcast_store, error_type: "serialization_error")
        expect(store.error_description).to eq("Failed to serialize broadcast data")
      end

      it "describes validation_error" do
        store = build_stubbed(:failed_broadcast_store, error_type: "validation_error")
        expect(store.error_description).to eq("Validation failed during broadcast")
      end

      it "truncates long error messages for unknown types" do
        long_message = "A" * 200
        store = build_stubbed(:failed_broadcast_store,
          error_type: "unknown",
          error_message: long_message
        )
        expect(store.error_description.length).to eq(100)
        expect(store.error_description).to end_with("...")
      end
    end

    describe "#age" do
      it "calculates time since failure" do
        failed_time = Time.new(2024, 1, 1, 10, 0, 0)
        current_time = Time.new(2024, 1, 1, 12, 30, 0)

        store = build_stubbed(:failed_broadcast_store, failed_at: failed_time)
        allow(Time).to receive(:current).and_return(current_time)

        expect(store.age).to eq(2.5.hours)
      end
    end

    describe "#stale?" do
      context "when older than a week and recovered" do
        it "returns true" do
          store = build_stubbed(:failed_broadcast_store,
            failed_at: 2.weeks.ago,
            recovered_at: 1.week.ago
          )
          allow(store).to receive(:age).and_return(2.weeks)
          expect(store.stale?).to be true
        end
      end

      context "when older than a week and max retries reached" do
        it "returns true" do
          store = build_stubbed(:failed_broadcast_store,
            failed_at: 2.weeks.ago,
            recovered_at: nil,
            retry_count: 3,
            priority: "medium"
          )
          allow(store).to receive(:age).and_return(2.weeks)
          allow(FailedBroadcastStore).to receive(:max_retry_attempts).with("medium").and_return(3)
          expect(store.stale?).to be true
        end
      end

      context "when recent" do
        it "returns false" do
          store = build_stubbed(:failed_broadcast_store, failed_at: 1.day.ago)
          allow(store).to receive(:age).and_return(1.day)
          expect(store.stale?).to be false
        end
      end
    end

    describe "#retry_broadcast!" do
      let(:store) { build_stubbed(:failed_broadcast_store,
        channel_name: "TestChannel",
        target_type: "Expense",
        target_id: 123,
        data: { "key" => "value" },
        priority: "high",
        retry_count: 1
      ) }

      context "when cannot retry" do
        it "returns false" do
          allow(store).to receive(:can_retry?).and_return(false)
          expect(store.retry_broadcast!).to be false
        end
      end

      context "when target not found" do
        it "updates error type and returns false" do
          allow(store).to receive(:can_retry?).and_return(true)
          expect(Expense).to receive(:find).with(123).and_raise(ActiveRecord::RecordNotFound.new("Not found"))

          expect(store).to receive(:update!).with(
            error_type: "record_not_found",
            error_message: match(/Target no longer exists/)
          )

          expect(store.retry_broadcast!).to be false
        end
      end

      context "when broadcast fails with error" do
        it "updates error information and returns false" do
          allow(store).to receive(:can_retry?).and_return(true)
          target = double("expense")
          expect(Expense).to receive(:find).with(123).and_return(target)
          expect(store).to receive(:increment!).with(:retry_count)

          error = StandardError.new("Broadcast failed")
          expect(BroadcastReliabilityService).to receive(:broadcast_with_retry).and_raise(error)
          expect(FailedBroadcastStore).to receive(:classify_error).with(error).and_return("unknown")

          expect(store).to receive(:update!).with(
            error_type: "unknown",
            error_message: "Broadcast failed"
          )

          expect(Rails.logger).to receive(:error).with(match(/Retry error/))

          expect(store.retry_broadcast!).to be false
        end
      end
    end
  end

  describe "edge cases" do
    describe "JSON data handling" do
      it "handles complex nested data" do
        complex_data = {
          "nested" => {
            "array" => [ 1, 2, 3 ],
            "hash" => { "key" => "value" }
          }
        }
        store = build_stubbed(:failed_broadcast_store, data: complex_data)
        expect(store.data).to eq(complex_data)
      end

      it "handles empty data" do
        store = build_stubbed(:failed_broadcast_store, data: {})
        expect(store).to be_valid
      end
    end

    describe "concurrent retry handling" do
      it "prevents duplicate retries" do
        store = build_stubbed(:failed_broadcast_store, retry_count: 2)

        # Mock the update! method to prevent database access
        allow(store).to receive(:update!)
        allow(store).to receive(:increment!)

        # Simulate that the retry count check fails after first call
        allow(store).to receive(:can_retry?).and_return(true, false)

        # The second call should return false due to can_retry? returning false
        expect(store.retry_broadcast!).to be false
      end
    end

    describe "priority edge cases" do
      it "handles nil priority in max_retry_attempts" do
        expect(FailedBroadcastStore.max_retry_attempts(nil)).to eq(3)
      end

      it "handles empty string priority" do
        expect(FailedBroadcastStore.max_retry_attempts("")).to eq(3)
      end
    end
  end
end

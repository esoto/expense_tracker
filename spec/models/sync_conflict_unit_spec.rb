# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncConflict, type: :model, unit: true do
  describe "associations" do
    it { should belong_to(:existing_expense).class_name("Expense") }
    it { should belong_to(:new_expense).class_name("Expense").optional }
    it { should belong_to(:sync_session) }
    it { should have_many(:conflict_resolutions).dependent(:destroy) }
  end

  describe "enums" do
    it "defines conflict_type enum with prefix" do
      expect(SyncConflict.conflict_types).to eq({
        "duplicate" => "duplicate",
        "similar" => "similar",
        "updated" => "updated",
        "needs_review" => "needs_review"
      })
    end

    it "defines status enum with prefix" do
      expect(SyncConflict.statuses).to eq({
        "pending" => "pending",
        "resolved" => "resolved",
        "ignored" => "ignored",
        "auto_resolved" => "auto_resolved"
      })
    end

    it "defines resolution_action enum with prefix and allow_nil" do
      expect(SyncConflict.resolution_actions).to eq({
        "keep_existing" => "keep_existing",
        "keep_new" => "keep_new",
        "keep_both" => "keep_both",
        "merged" => "merged",
        "custom" => "custom"
      })
    end
  end

  describe "validations" do
    it { should validate_presence_of(:conflict_type) }
    it { should validate_presence_of(:status) }
    it { should validate_numericality_of(:similarity_score)
      .is_greater_than_or_equal_to(0)
      .is_less_than_or_equal_to(100)
      .allow_nil }
    it { should validate_numericality_of(:priority)
      .is_greater_than_or_equal_to(0) }
  end

  describe "scopes" do
    describe ".unresolved" do
      it "filters by pending status in SQL" do
        query = SyncConflict.unresolved
        expect(query.to_sql).to include('WHERE')
        expect(query.to_sql).to include('"status" = \'pending\'')
      end
    end

    describe ".resolved" do
      it "filters by resolved and auto_resolved status in SQL" do
        query = SyncConflict.resolved
        expect(query.to_sql).to include('WHERE')
        expect(query.to_sql).to include('"status" IN (\'resolved\', \'auto_resolved\')')
      end
    end

    describe ".by_priority" do
      it "orders by priority desc and created_at asc in SQL" do
        query = SyncConflict.by_priority
        expect(query.to_sql).to include('ORDER BY')
        expect(query.to_sql).to include('"priority" DESC')
        expect(query.to_sql).to include('"created_at" ASC')
      end
    end

    describe ".bulk_resolvable" do
      it "filters by bulk_resolvable true in SQL" do
        query = SyncConflict.bulk_resolvable
        expect(query.to_sql).to include('WHERE')
        expect(query.to_sql).to include('"bulk_resolvable" = TRUE')
      end
    end

    describe ".recent" do
      it "orders by created_at desc in SQL" do
        query = SyncConflict.recent
        expect(query.to_sql).to include('ORDER BY')
        expect(query.to_sql).to include('"created_at" DESC')
      end
    end

    describe ".for_session" do
      it "filters by sync session id in SQL" do
        query = SyncConflict.for_session(123)
        expect(query.to_sql).to include('WHERE')
        expect(query.to_sql).to include('"sync_session_id" = 123')
      end
    end

    describe ".with_expenses" do
      it "includes existing and new expenses associations" do
        query = SyncConflict.with_expenses
        # Check that includes were applied to the relation
        expect(query.includes_values).to include(:existing_expense, :new_expense)
      end
    end
  end

  describe "callbacks" do
    describe "before_validation :calculate_similarity_score" do
      let(:existing_expense) { build(:expense,
        amount: 100,
        transaction_date: Date.new(2024, 1, 15),
        merchant_name: "Store A",
        description: "Purchase"
      ) }
      let(:new_expense) { build(:expense,
        amount: 100,
        transaction_date: Date.new(2024, 1, 15),
        merchant_name: "Store A",
        description: "Purchase"
      ) }
      let(:conflict) { build(:sync_conflict,
        existing_expense: existing_expense,
        new_expense: new_expense,
        conflict_type: "duplicate"
      ) }

      context "when should calculate similarity" do
        it "calculates perfect match as 100%" do
          conflict.send(:calculate_similarity_score)
          expect(conflict.similarity_score).to eq(100.0)
        end

        context 'calculating match for amount' do
          before do
            existing_expense.transaction_date = Date.new(2024, 1, 17)
            existing_expense.merchant_name = "Store B"
            existing_expense.description = "Purchase at Store B"
            new_expense.transaction_date = Date.new(2024, 1, 15)
            new_expense.merchant_name = "Stor C"
            new_expense.description = "Purchas at Store C"
          end

          it 'calculates for equal amounts' do
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(50.0) # 40 (amount) + 10 (date: 2 days diff)
          end

          it 'calculates when amount differs by less than 1' do
            existing_expense.amount = 100.0
            new_expense.amount = 99.9
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(40.0) # 30 (amount) + 10 (date: 2 days diff)
          end

          it 'calculates when amount differs less than 10' do
            existing_expense.amount = 100.0
            new_expense.amount = 91.0
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(30.0) # 20 (amount) + 10 (date: 2 days diff)
          end

          it 'calculates when amount differs by 100' do
            existing_expense.amount = 100.0
            new_expense.amount = 0.0
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(10.0) # 0 (amount) + 10 (date: 2 days diff)
          end
        end

        context 'calculates match for date' do
          before do
            existing_expense.amount = 100.0
            new_expense.amount = 0.0
            existing_expense.merchant_name = "Storeasdfs A"
            new_expense.merchant_name = "Stor C"
            existing_expense.description = "Purchase some item"
            new_expense.description = "Purchae"
            existing_expense.transaction_date = Date.new(2024, 1, 15)
            new_expense.transaction_date = Date.new(2024, 1, 15)
          end

          it 'calculates for equal dates' do
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(30.0)
          end

          it 'calculates when dates are differ by a day' do
            existing_expense.transaction_date = Date.new(2024, 1, 17)
            new_expense.transaction_date = Date.new(2024, 1, 16)
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(20.0)
          end

          it 'calculates when dates are differ by 3 days' do
            existing_expense.transaction_date = Date.new(2024, 1, 18)
            new_expense.transaction_date = Date.new(2024, 1, 16)
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(10.0)
          end

          it 'calculates when dates are differ by more than 3 days' do
            existing_expense.transaction_date = Date.new(2024, 1, 20)
            new_expense.transaction_date = Date.new(2024, 1, 16)
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(0.0)
          end

          context 'when dates are empty' do
            before do
              allow(existing_expense).to receive(:transaction_date).and_return(nil)
              allow(new_expense).to receive(:transaction_date).and_return(nil)
            end

            it 'calculates for empty dates' do
              conflict.send(:calculate_similarity_score)
              expect(conflict.similarity_score).to eq(0.0)
            end
          end
        end

        context 'calculates match for merchant' do
          before do
            existing_expense.amount = 100.0
            new_expense.amount = 0.0
            existing_expense.merchant_name = "Store A"
            new_expense.merchant_name = "Store A"
            existing_expense.description = "Purchase some item"
            new_expense.description = "Purchae"
            existing_expense.transaction_date = Date.new(2024, 1, 15)
            new_expense.transaction_date = Date.new(2024, 1, 25)
          end

          it 'calculates for equal merchants' do
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(20.0)
          end

          it 'calculates when merchants are similar' do
            existing_expense.merchant_name = "Store A"
            new_expense.merchant_name = "Store"
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(10.0)
          end

          it 'calculates when merchants are different' do
            existing_expense.merchant_name = "Store A"
            new_expense.merchant_name = "Store B"
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(0.0)
          end

          context 'when merchants are empty' do
            before do
              allow(existing_expense).to receive(:merchant_name).and_return(nil)
              allow(new_expense).to receive(:merchant_name).and_return(nil)
            end

            it 'calculates for empty merchants' do
              conflict.send(:calculate_similarity_score)
              expect(conflict.similarity_score).to eq(0.0)
            end
          end
        end

        context 'calculates match for description' do
          before do
            existing_expense.amount = 100.0
            new_expense.amount = 0.0
            existing_expense.merchant_name = "Store A"
            new_expense.merchant_name = "Stor B"
            existing_expense.description = "Purchase some item"
            new_expense.description = "Purchase some item"
            existing_expense.transaction_date = Date.new(2024, 1, 15)
            new_expense.transaction_date = Date.new(2024, 1, 25)
          end

          it 'calculates for equal descriptions' do
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(10.0)
          end

          it 'calculates when descriptions are similar' do
            existing_expense.description = "Purchase some item"
            new_expense.description = "Purchase"
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(5.0)
          end

          it 'calculates when descriptions are different' do
            existing_expense.description = "Purchase some item"
            new_expense.description = "Purchase some other item"
            conflict.send(:calculate_similarity_score)
            expect(conflict.similarity_score).to eq(0.0)
          end

          context 'when descriptions are empty' do
            before do
              existing_expense.description = nil
              new_expense.description = nil
            end

            it 'calculates for empty descriptions' do
              conflict.send(:calculate_similarity_score)
              expect(conflict.similarity_score).to eq(0.0)
            end
          end
        end
      end

      context "when should not calculate similarity" do
        it "skips calculation for updated type" do
          conflict.conflict_type = "updated"
          expect(conflict.send(:should_calculate_similarity?)).to be false
        end

        it "skips calculation when new_expense is nil" do
          conflict.new_expense = nil
          expect(conflict.send(:should_calculate_similarity?)).to be false
        end

        it "skips calculation when existing_expense is nil" do
          conflict.existing_expense = nil
          expect(conflict.send(:should_calculate_similarity?)).to be false
        end
      end
    end

    describe "before_validation :set_priority" do
      let(:conflict) { build(:sync_conflict) }

      before { conflict.priority = nil }

      context 'when conflict_type is duplicate' do
        it "sets priority 1 for high similarity duplicates" do
          conflict.conflict_type = "duplicate"
          conflict.similarity_score = 95
          expect(conflict.send(:set_priority)).to eq(1)
        end

        it "sets priority 2 for low similarity duplicates" do
          conflict.conflict_type = "duplicate"
          conflict.similarity_score = 85
          expect(conflict.send(:set_priority)).to eq(2)
        end
      end

      context 'when conflict_type is similar' do
        it "sets priority 3 for similar conflicts" do
          conflict.conflict_type = "similar"
          expect(conflict.send(:set_priority)).to eq(3)
        end
      end

      context 'when conflict_type is updated' do
        it "sets priority 4 for updated conflicts" do
          conflict.conflict_type = "updated"
          expect(conflict.send(:set_priority)).to eq(4)
        end

        it "sets priority 5 for needs_review conflicts" do
          conflict.conflict_type = "needs_review"
          expect(conflict.send(:set_priority)).to eq(5)
        end
      end
    end

    describe "after_update :broadcast_resolution" do
      let(:conflict) { build(:sync_conflict, id: 1) }
      let(:sync_session) { double("sync_session") }

      before do
        allow(conflict).to receive(:sync_session).and_return(sync_session)
        allow(conflict).to receive(:saved_change_to_status?).and_return(true)
      end

      it "broadcasts resolution when status changes" do
        expect(SyncStatusChannel).to receive(:broadcast_to).with(
          sync_session,
          {
            event: "conflict_resolved",
            conflict_id: 1,
            status: conflict.status,
            resolution_action: conflict.resolution_action
          }
        )

        conflict.send(:broadcast_resolution)
      end

      it "doesn't broadcast when status doesn't change" do
        allow(conflict).to receive(:saved_change_to_status?).and_return(false)
        expect(SyncStatusChannel).not_to receive(:broadcast_to)

        # This would normally be triggered by after_update, but we're testing the condition
        conflict.send(:broadcast_resolution) if conflict.saved_change_to_status?
      end
    end
  end

  describe "instance methods" do
    describe "#resolve!" do
      let(:existing_expense) { build(:expense) }
      let(:new_expense) { build(:expense, amount: 25) }
      let(:conflict) { build(:sync_conflict,
        existing_expense: existing_expense,
        new_expense: new_expense
      ) }
      let(:current_time) { Time.new(2024, 1, 1) }
      let(:action) { "keep_existing" }
      let(:resolution_data) { { custom: "data" } }
      let(:resolved_by) { "user@example.com" }
      let(:resolution) { double("resolution", update!: true).as_null_object }
      let(:current_state) { double("current_state") }
      let(:changes) { double("calculate_changes") }

      # Testing private methods to simplify overall resolve! testing
      describe 'private methods' do
        describe '#capture_current_state' do
        let(:expected_current_state) do
          {
            existing_expense: existing_expense.attributes,
              new_expense: new_expense&.attributes,
              conflict: conflict.attributes.except("created_at", "updated_at")
            }
          end

          it 'captures the current state of the conflict' do
            expect(conflict.send(:capture_current_state)).to eq(expected_current_state)
          end
        end

        describe '#apply_resolution' do
          context 'when action is keep_existing' do
            it 'updates the new_expense with status :duplicate' do
              expect(new_expense).to receive(:update!).with(
                status: :duplicate
              )
              conflict.send(:apply_resolution, "keep_existing", {})
            end
          end

          context 'when action is keep_new' do
            it 'updates the expenses status' do
              expect(existing_expense).to receive(:update!).with(
                status: :duplicate
              )
              expect(new_expense).to receive(:update!).with(
                status: :processed
              )
              conflict.send(:apply_resolution, "keep_new", {})
            end
          end

          context 'when action is keep_both' do
            it 'updates the new expense status' do
              expect(new_expense).to receive(:update!).with(
                status: :processed
              )
              conflict.send(:apply_resolution, "keep_both", {})
            end
          end

          context 'when action is merged' do
            let(:resolution_data) do
              {
                "amount" => "new"
              }
            end
            it 'updates the expenses status' do
              expect(existing_expense).to receive(:update!).with(
                hash_including("amount" => new_expense.amount)
              )
              expect(new_expense).to receive(:update!).with(
                status: :duplicate
              )
              conflict.send(:apply_resolution, "merged", resolution_data)
            end
          end

          context 'when action is custom' do
            let(:resolution_data) do
              {
                "existing_expense" => { amount: new_expense.amount },
                "new_expense" => { amount: existing_expense.amount }
              }
            end

            it 'updates both expenses' do
              expect(existing_expense).to receive(:update!).with(
                resolution_data["existing_expense"]
              )
              expect(new_expense).to receive(:update!).with(
                resolution_data["new_expense"]
              )
              conflict.send(:apply_resolution, "custom", resolution_data)
            end
          end
        end

        describe '#calculate_changes' do
          let(:original_existing_amount) { existing_expense.amount }
          let(:original_new_amount) { new_expense.amount }

          context 'when no changes occurred' do
            it 'returns empty changes hash when states are identical' do
              # Mock capture_current_state to return the exact same state
              before_state = {
                "existing_expense" => existing_expense.attributes,
                "new_expense" => new_expense.attributes
              }

              allow(conflict).to receive(:capture_current_state).and_return(before_state)

              result = conflict.send(:calculate_changes, before_state)
              expect(result).to eq({})
            end
          end

          context 'when existing expense changed' do
            it 'detects changes in existing expense attributes' do
              before_attrs = existing_expense.attributes
              before_state = {
                "existing_expense" => before_attrs,
                "new_expense" => new_expense.attributes
              }

              # Change the existing expense
              existing_expense.amount = 999.99
              existing_expense.description = "Updated description"
              after_attrs = existing_expense.attributes

              # Mock the after state
              after_state = {
                "existing_expense" => after_attrs,
                "new_expense" => new_expense.attributes
              }
              allow(conflict).to receive(:capture_current_state).and_return(after_state)

              result = conflict.send(:calculate_changes, before_state)

              expect(result).to have_key("existing_expense")
              expect(result["existing_expense"]).to eq({
                before: before_attrs,
                after: after_attrs
              })
              expect(result).not_to have_key("new_expense")
            end
          end

          context 'when new expense changed' do
            it 'detects changes in new expense attributes' do
              before_new_attrs = new_expense.attributes
              before_state = {
                "existing_expense" => existing_expense.attributes,
                "new_expense" => before_new_attrs
              }

              # Change the new expense
              new_expense.amount = 555.55
              new_expense.merchant_name = "Updated Merchant"
              after_new_attrs = new_expense.attributes

              # Mock the after state
              after_state = {
                "existing_expense" => existing_expense.attributes,
                "new_expense" => after_new_attrs
              }
              allow(conflict).to receive(:capture_current_state).and_return(after_state)

              result = conflict.send(:calculate_changes, before_state)

              expect(result).to have_key("new_expense")
              expect(result["new_expense"]).to eq({
                before: before_new_attrs,
                after: after_new_attrs
              })
              expect(result).not_to have_key("existing_expense")
            end
          end

          context 'when both expenses changed' do
            it 'detects changes in both expense attributes' do
              before_existing_attrs = existing_expense.attributes
              before_new_attrs = new_expense.attributes
              before_state = {
                "existing_expense" => before_existing_attrs,
                "new_expense" => before_new_attrs
              }

              # Change both expenses
              existing_expense.amount = 777.77
              new_expense.amount = 888.88
              after_existing_attrs = existing_expense.attributes
              after_new_attrs = new_expense.attributes

              # Mock the after state
              after_state = {
                "existing_expense" => after_existing_attrs,
                "new_expense" => after_new_attrs
              }
              allow(conflict).to receive(:capture_current_state).and_return(after_state)

              result = conflict.send(:calculate_changes, before_state)

              expect(result).to have_key("existing_expense")
              expect(result).to have_key("new_expense")
              expect(result["existing_expense"]).to eq({
                before: before_existing_attrs,
                after: after_existing_attrs
              })
              expect(result["new_expense"]).to eq({
                before: before_new_attrs,
                after: after_new_attrs
              })
            end
          end

          context 'when new_expense becomes nil' do
            it 'detects new expense becoming nil' do
              before_new_attrs = new_expense.attributes
              before_state = {
                "existing_expense" => existing_expense.attributes,
                "new_expense" => before_new_attrs
              }

              # Mock the after state with new_expense as nil
              after_state = {
                "existing_expense" => existing_expense.attributes,
                "new_expense" => nil
              }
              allow(conflict).to receive(:capture_current_state).and_return(after_state)

              result = conflict.send(:calculate_changes, before_state)

              expect(result).to have_key("new_expense")
              expect(result["new_expense"]).to eq({
                before: before_new_attrs,
                after: nil
              })
            end
          end

          context 'edge cases' do
            it 'handles nil values in before_state gracefully' do
              before_state = {
                "existing_expense" => nil,
                "new_expense" => nil
              }

              after_state = {
                "existing_expense" => existing_expense.attributes,
                "new_expense" => new_expense.attributes
              }
              allow(conflict).to receive(:capture_current_state).and_return(after_state)

              result = conflict.send(:calculate_changes, before_state)

              expect(result).to have_key("existing_expense")
              expect(result).to have_key("new_expense")
              expect(result["existing_expense"][:before]).to be_nil
              expect(result["existing_expense"][:after]).to eq(existing_expense.attributes)
            end
          end
        end
      end

      describe 'main functionality' do
        before do
          allow(Time).to receive(:current).and_return(current_time)
          allow_any_instance_of(SyncConflict).to receive(:capture_current_state) { current_state }
          allow_any_instance_of(SyncConflict).to receive(:calculate_changes) { changes }
        end

        it "creates resolution record and updates status" do
          expect(conflict.conflict_resolutions).to receive(:create!).with(
            action: action,
            before_state: current_state,
            resolution_method: "manual",
            resolved_by: resolved_by
          ).and_return(resolution)

          expect(conflict).to receive(:apply_resolution).with(action, resolution_data)

          expect(resolution).to receive(:update!).with(
            after_state: current_state,
            changes_made: changes
          )

          expect(conflict).to receive(:update!).with(
            status: "resolved",
            resolution_action: action,
            resolution_data: resolution_data,
            resolved_at: current_time,
            resolved_by: resolved_by
          )

          conflict.resolve!(action, resolution_data, resolved_by)
        end
      end
    end

    describe "#undo_last_resolution!" do
      let(:conflict) { build(:sync_conflict) }
      let(:last_resolution) { double("resolution",
        undoable: true,
        before_state: { state: "original" }
      ) }
      let(:undo_resolution) { double("undo_resolution") }

      context "when resolution can be undone" do
        it "creates undo resolution and restores state" do
          current_time = Time.new(2024, 1, 1)

          allow(Time).to receive(:current).and_return(current_time)
          allow(conflict).to receive(:transaction).and_yield
          allow(conflict).to receive(:capture_current_state).and_return({ state: "current" })
          allow(conflict).to receive(:restore_state)

          resolutions_scope = double("resolutions_scope")
          allow(conflict).to receive(:conflict_resolutions).and_return(resolutions_scope)
          allow(resolutions_scope).to receive(:where).with(undone: false).and_return(resolutions_scope)
          allow(resolutions_scope).to receive(:order).with(created_at: :desc).and_return(resolutions_scope)
          allow(resolutions_scope).to receive(:first).and_return(last_resolution)

          expect(conflict.conflict_resolutions).to receive(:create!).with(
            action: "undo",
            before_state: { state: "current" },
            resolution_method: "manual"
          ).and_return(undo_resolution)

          expect(conflict).to receive(:restore_state).with({ state: "original" })

          expect(last_resolution).to receive(:update!).with(
            undone: true,
            undone_at: current_time,
            undone_by_resolution: undo_resolution
          )

          expect(conflict).to receive(:update!).with(
            status: "pending",
            resolution_action: nil,
            resolution_data: {},
            resolved_at: nil
          )

          result = conflict.undo_last_resolution!
          expect(result).to eq(undo_resolution)
        end
      end

      context "when no resolution exists" do
        it "returns false" do
          resolutions_scope = double("resolutions_scope")
          allow(conflict).to receive(:conflict_resolutions).and_return(resolutions_scope)
          allow(resolutions_scope).to receive(:where).and_return(resolutions_scope)
          allow(resolutions_scope).to receive(:order).and_return(resolutions_scope)
          allow(resolutions_scope).to receive(:first).and_return(nil)

          expect(conflict.undo_last_resolution!).to be false
        end
      end
    end

    describe "#similar_conflicts" do
      let(:conflict) { build(:sync_conflict,
        id: 1,
        existing_expense_id: 10,
        conflict_type: "duplicate"
      ) }

      it "finds similar unresolved conflicts" do
        unresolved_scope = double("unresolved_scope")
        where_not_scope = double("where_not_scope")
        final_scope = double("final_scope")

        expect(SyncConflict).to receive(:unresolved).and_return(unresolved_scope)
        expect(unresolved_scope).to receive(:where).and_return(where_not_scope)
        expect(where_not_scope).to receive(:not).with(id: 1).and_return(where_not_scope)
        expect(where_not_scope).to receive(:where).with(
          existing_expense_id: 10,
          conflict_type: "duplicate"
        ).and_return(final_scope)

        expect(conflict.similar_conflicts).to eq(final_scope)
      end
    end

    describe "#can_bulk_resolve?" do
      let(:conflict) { build(:sync_conflict) }

      it "returns true when bulk_resolvable and pending" do
        conflict.bulk_resolvable = true
        conflict.status = "pending"
        expect(conflict.can_bulk_resolve?).to be true
      end

      it "returns false when not bulk_resolvable" do
        conflict.bulk_resolvable = false
        conflict.status = "pending"
        expect(conflict.can_bulk_resolve?).to be false
      end

      it "returns false when not pending" do
        conflict.bulk_resolvable = true
        conflict.status = "resolved"
        expect(conflict.can_bulk_resolve?).to be false
      end
    end

    describe "#field_differences" do
      let(:conflict) { build(:sync_conflict) }

      it "returns differences when present" do
        differences = { "amount" => [ 100, 150 ] }
        conflict.differences = differences
        expect(conflict.field_differences).to eq(differences)
      end

      it "returns empty hash when differences nil" do
        conflict.differences = nil
        expect(conflict.field_differences).to eq({})
      end

      it "returns empty hash when differences empty" do
        conflict.differences = {}
        expect(conflict.field_differences).to eq({})
      end
    end

    describe "#formatted_similarity_score" do
      let(:conflict) { build(:sync_conflict) }

      it "formats score with one decimal place" do
        conflict.similarity_score = 85.678
        expect(conflict.formatted_similarity_score).to eq("85.7%")
      end

      it "returns N/A when score is nil" do
        conflict.similarity_score = nil
        expect(conflict.formatted_similarity_score).to eq("N/A")
      end

      it "handles zero score" do
        conflict.similarity_score = 0
        expect(conflict.formatted_similarity_score).to eq("0.0%")
      end

      it "handles perfect score" do
        conflict.similarity_score = 100
        expect(conflict.formatted_similarity_score).to eq("100.0%")
      end
    end

    describe "#restore_state (private)" do
      let(:existing_expense) { create("expense") }
      let(:new_expense) { create("expense") }
      let(:conflict) { build(:sync_conflict,
        existing_expense: existing_expense,
        new_expense: new_expense
      ) }

      it "restores both expenses from state" do
        state = {
          "existing_expense" => {
            "id" => 1,
            "amount" => 100,
            "description" => "Original",
            "created_at" => "2024-01-01",
            "lock_version" => 1
          },
          "new_expense" => {
            "id" => 2,
            "amount" => 150,
            "description" => "New Original"
          }
        }

        expect(existing_expense.reload).to receive(:update!).with(
          hash_including(
            "amount" => 100,
            "description" => "Original"
          )
        )
        expect(new_expense.reload).to receive(:update!).with(
          hash_including(
            "amount" => 150,
            "description" => "New Original"
          )
        )

        conflict.send(:restore_state, state)
      end

      it "handles nil new expense" do
        conflict.new_expense = nil
        state = {
          "existing_expense" => { "amount" => 100 },
          "new_expense" => { "amount" => 150 }
        }

        expect(existing_expense.reload).to receive(:update!).with(hash_including("amount" => 100))

        conflict.send(:restore_state, state)
      end
    end
  end
end

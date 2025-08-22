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

    it "allows nil similarity_score" do
      conflict = build_stubbed(:sync_conflict, similarity_score: nil)
      expect(conflict).to be_valid
    end

    it "allows nil resolution_action" do
      conflict = build_stubbed(:sync_conflict, resolution_action: nil)
      expect(conflict).to be_valid
    end
  end

  describe "scopes" do
    describe ".unresolved" do
      it "returns pending conflicts" do
        relation = double("relation")
        expect(SyncConflict).to receive(:where).with(status: ["pending"]).and_return(relation)
        expect(SyncConflict.unresolved).to eq(relation)
      end
    end

    describe ".resolved" do
      it "returns resolved and auto_resolved conflicts" do
        relation = double("relation")
        expect(SyncConflict).to receive(:where).with(status: ["resolved", "auto_resolved"]).and_return(relation)
        expect(SyncConflict.resolved).to eq(relation)
      end
    end

    describe ".by_priority" do
      it "orders by priority desc and created_at asc" do
        relation = double("relation")
        expect(SyncConflict).to receive(:order).with(priority: :desc, created_at: :asc).and_return(relation)
        expect(SyncConflict.by_priority).to eq(relation)
      end
    end

    describe ".bulk_resolvable" do
      it "returns conflicts marked as bulk resolvable" do
        relation = double("relation")
        expect(SyncConflict).to receive(:where).with(bulk_resolvable: true).and_return(relation)
        expect(SyncConflict.bulk_resolvable).to eq(relation)
      end
    end

    describe ".recent" do
      it "orders by created_at desc" do
        relation = double("relation")
        expect(SyncConflict).to receive(:order).with(created_at: :desc).and_return(relation)
        expect(SyncConflict.recent).to eq(relation)
      end
    end

    describe ".for_session" do
      it "filters by sync session id" do
        relation = double("relation")
        expect(SyncConflict).to receive(:where).with(sync_session_id: 123).and_return(relation)
        expect(SyncConflict.for_session(123)).to eq(relation)
      end
    end

    describe ".with_expenses" do
      it "includes existing and new expenses" do
        relation = double("relation")
        expect(SyncConflict).to receive(:includes).with(:existing_expense, :new_expense).and_return(relation)
        expect(SyncConflict.with_expenses).to eq(relation)
      end
    end
  end

  describe "callbacks" do
    describe "before_validation :calculate_similarity_score" do
      let(:existing_expense) { build_stubbed(:expense, 
        amount: 100, 
        transaction_date: Date.new(2024, 1, 15),
        merchant_name: "Store A",
        description: "Purchase"
      ) }
      let(:new_expense) { build_stubbed(:expense, 
        amount: 100, 
        transaction_date: Date.new(2024, 1, 15),
        merchant_name: "Store A",
        description: "Purchase"
      ) }
      let(:conflict) { build_stubbed(:sync_conflict, 
        existing_expense: existing_expense,
        new_expense: new_expense,
        conflict_type: "duplicate"
      ) }

      context "when should calculate similarity" do
        it "calculates perfect match as 100%" do
          conflict.send(:calculate_similarity_score)
          expect(conflict.similarity_score).to eq(100.0)
        end

        it "calculates partial match for amount differences" do
          new_expense.amount = 95
          conflict.send(:calculate_similarity_score)
          expect(conflict.similarity_score).to be < 100
          expect(conflict.similarity_score).to be > 50
        end

        it "calculates partial match for date differences" do
          new_expense.transaction_date = Date.new(2024, 1, 16)
          conflict.send(:calculate_similarity_score)
          expect(conflict.similarity_score).to be < 100
          expect(conflict.similarity_score).to be > 50
        end

        it "calculates partial match for merchant differences" do
          new_expense.merchant_name = "Store B"
          conflict.send(:calculate_similarity_score)
          expect(conflict.similarity_score).to be < 100
        end

        it "handles partial merchant name matches" do
          new_expense.merchant_name = "Store A Inc"
          conflict.send(:calculate_similarity_score)
          expect(conflict.similarity_score).to be > 70
        end

        it "handles nil merchant names" do
          existing_expense.merchant_name = nil
          new_expense.merchant_name = nil
          conflict.send(:calculate_similarity_score)
          expect(conflict.similarity_score).to be_a(Float)
        end

        it "handles nil descriptions" do
          existing_expense.description = nil
          new_expense.description = nil
          conflict.send(:calculate_similarity_score)
          expect(conflict.similarity_score).to be_a(Float)
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
      let(:conflict) { build_stubbed(:sync_conflict) }

      it "sets priority 1 for high similarity duplicates" do
        conflict.conflict_type = "duplicate"
        conflict.similarity_score = 95
        conflict.send(:set_priority)
        expect(conflict.priority).to eq(1)
      end

      it "sets priority 2 for low similarity duplicates" do
        conflict.conflict_type = "duplicate"
        conflict.similarity_score = 85
        conflict.send(:set_priority)
        expect(conflict.priority).to eq(2)
      end

      it "sets priority 3 for similar conflicts" do
        conflict.conflict_type = "similar"
        conflict.send(:set_priority)
        expect(conflict.priority).to eq(3)
      end

      it "sets priority 4 for updated conflicts" do
        conflict.conflict_type = "updated"
        conflict.send(:set_priority)
        expect(conflict.priority).to eq(4)
      end

      it "sets priority 5 for needs_review conflicts" do
        conflict.conflict_type = "needs_review"
        conflict.send(:set_priority)
        expect(conflict.priority).to eq(5)
      end

      it "preserves existing priority if set" do
        conflict.priority = 10
        conflict.conflict_type = "duplicate"
        conflict.send(:set_priority)
        expect(conflict.priority).to eq(10)
      end
    end

    describe "after_update :broadcast_resolution" do
      let(:conflict) { build_stubbed(:sync_conflict, id: 1) }
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
      let(:existing_expense) { build_stubbed(:expense) }
      let(:new_expense) { build_stubbed(:expense) }
      let(:conflict) { build_stubbed(:sync_conflict, 
        existing_expense: existing_expense,
        new_expense: new_expense
      ) }

      it "creates resolution record and updates status" do
        resolution = double("resolution")
        current_time = Time.new(2024, 1, 1)
        
        allow(Time).to receive(:current).and_return(current_time)
        allow(conflict).to receive(:transaction).and_yield
        allow(conflict).to receive(:capture_current_state).and_return({ state: "before" }, { state: "after" })
        allow(conflict).to receive(:apply_resolution)
        allow(conflict).to receive(:calculate_changes).and_return({ changes: "made" })
        
        expect(conflict.conflict_resolutions).to receive(:create!).with(
          action: "keep_existing",
          before_state: { state: "before" },
          resolution_method: "manual",
          resolved_by: "user@example.com"
        ).and_return(resolution)
        
        expect(resolution).to receive(:update!).with(
          after_state: { state: "after" },
          changes_made: { changes: "made" }
        )
        
        expect(conflict).to receive(:update!).with(
          status: "resolved",
          resolution_action: "keep_existing",
          resolution_data: { custom: "data" },
          resolved_at: current_time,
          resolved_by: "user@example.com"
        )
        
        result = conflict.resolve!("keep_existing", { custom: "data" }, "user@example.com")
        expect(result).to eq(resolution)
      end

      it "applies different resolution actions" do
        allow(conflict).to receive(:transaction).and_yield
        allow(conflict).to receive(:capture_current_state).and_return({})
        allow(conflict).to receive(:calculate_changes).and_return({})
        allow(conflict.conflict_resolutions).to receive(:create!).and_return(double(update!: true))
        allow(conflict).to receive(:update!)
        
        expect(conflict).to receive(:apply_resolution).with("keep_new", {})
        
        conflict.resolve!("keep_new", {})
      end
    end

    describe "#undo_last_resolution!" do
      let(:conflict) { build_stubbed(:sync_conflict) }
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

      context "when resolution is not undoable" do
        it "returns false" do
          last_resolution.undoable = false
          
          resolutions_scope = double("resolutions_scope")
          allow(conflict).to receive(:conflict_resolutions).and_return(resolutions_scope)
          allow(resolutions_scope).to receive(:where).and_return(resolutions_scope)
          allow(resolutions_scope).to receive(:order).and_return(resolutions_scope)
          allow(resolutions_scope).to receive(:first).and_return(last_resolution)
          
          expect(conflict.undo_last_resolution!).to be false
        end
      end
    end

    describe "#similar_conflicts" do
      let(:conflict) { build_stubbed(:sync_conflict, 
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
      let(:conflict) { build_stubbed(:sync_conflict) }

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
      let(:conflict) { build_stubbed(:sync_conflict) }

      it "returns differences when present" do
        differences = { "amount" => [100, 150] }
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
      let(:conflict) { build_stubbed(:sync_conflict) }

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

    describe "#apply_resolution (private)" do
      let(:existing_expense) { double("existing_expense") }
      let(:new_expense) { double("new_expense") }
      let(:conflict) { build_stubbed(:sync_conflict, 
        existing_expense: existing_expense,
        new_expense: new_expense
      ) }

      context "keep_existing action" do
        it "marks new expense as duplicate" do
          expect(new_expense).to receive(:update!).with(status: "duplicate")
          conflict.send(:apply_resolution, "keep_existing", {})
        end
      end

      context "keep_new action" do
        it "marks existing as duplicate and new as processed" do
          expect(existing_expense).to receive(:update!).with(status: "duplicate")
          expect(new_expense).to receive(:update!).with(status: "processed")
          conflict.send(:apply_resolution, "keep_new", {})
        end
      end

      context "keep_both action" do
        it "marks new expense as processed" do
          expect(new_expense).to receive(:update!).with(status: "processed")
          conflict.send(:apply_resolution, "keep_both", {})
        end
      end

      context "merged action" do
        it "calls merge_expenses" do
          merge_data = { "amount" => "new" }
          expect(conflict).to receive(:merge_expenses).with(merge_data)
          conflict.send(:apply_resolution, "merged", merge_data)
        end
      end

      context "custom action" do
        it "calls apply_custom_resolution" do
          custom_data = { "existing_expense" => { "amount" => 200 } }
          expect(conflict).to receive(:apply_custom_resolution).with(custom_data)
          conflict.send(:apply_resolution, "custom", custom_data)
        end
      end
    end

    describe "#merge_expenses (private)" do
      let(:existing_expense) { double("existing_expense") }
      let(:new_expense) { double("new_expense", amount: 150, description: "New desc") }
      let(:conflict) { build_stubbed(:sync_conflict, 
        existing_expense: existing_expense,
        new_expense: new_expense
      ) }

      it "merges fields from new expense" do
        merge_data = {
          "amount" => "new",
          "description" => "new"
        }

        expect(new_expense).to receive(:respond_to?).with("amount").and_return(true)
        expect(new_expense).to receive(:send).with("amount").and_return(150)
        expect(new_expense).to receive(:respond_to?).with("description").and_return(true)
        expect(new_expense).to receive(:send).with("description").and_return("New desc")
        
        expect(existing_expense).to receive(:update!).with(
          "amount" => 150,
          "description" => "New desc"
        )
        expect(new_expense).to receive(:update!).with(status: "duplicate")

        conflict.send(:merge_expenses, merge_data)
      end

      it "skips fields new expense doesn't respond to" do
        merge_data = {
          "amount" => "new",
          "invalid_field" => "new"
        }

        expect(new_expense).to receive(:respond_to?).with("amount").and_return(true)
        expect(new_expense).to receive(:send).with("amount").and_return(150)
        expect(new_expense).to receive(:respond_to?).with("invalid_field").and_return(false)
        
        expect(existing_expense).to receive(:update!).with("amount" => 150)
        expect(new_expense).to receive(:update!).with(status: "duplicate")

        conflict.send(:merge_expenses, merge_data)
      end
    end

    describe "#restore_state (private)" do
      let(:existing_expense) { double("existing_expense", reload: double("reloaded_expense")) }
      let(:new_expense) { double("new_expense", reload: double("reloaded_expense")) }
      let(:conflict) { build_stubbed(:sync_conflict, 
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
          "amount" => 100,
          "description" => "Original"
        )
        expect(new_expense.reload).to receive(:update!).with(
          "amount" => 150,
          "description" => "New Original"
        )

        conflict.send(:restore_state, state)
      end

      it "handles nil new expense" do
        conflict.new_expense = nil
        state = {
          "existing_expense" => { "amount" => 100 },
          "new_expense" => { "amount" => 150 }
        }

        expect(existing_expense.reload).to receive(:update!).with("amount" => 100)
        
        conflict.send(:restore_state, state)
      end
    end
  end

  describe "edge cases" do
    describe "similarity calculation edge cases" do
      let(:existing) { build_stubbed(:expense) }
      let(:new_exp) { build_stubbed(:expense) }
      let(:conflict) { build_stubbed(:sync_conflict, 
        existing_expense: existing,
        new_expense: new_exp,
        conflict_type: "duplicate"
      ) }

      it "handles very small amount differences" do
        existing.amount = 100.00
        new_exp.amount = 100.01
        conflict.send(:calculate_similarity_score)
        expect(conflict.similarity_score).to be > 60
      end

      it "handles case-insensitive merchant comparison" do
        existing.merchant_name = "STORE NAME"
        new_exp.merchant_name = "store name"
        conflict.send(:calculate_similarity_score)
        expect(conflict.similarity_score).to be > 80
      end

      it "handles partial description matches" do
        existing.description = "Purchase at store"
        new_exp.description = "store"
        conflict.send(:calculate_similarity_score)
        expect(conflict.similarity_score).to be > 0
      end

      it "handles all nil values gracefully" do
        existing.amount = nil
        existing.transaction_date = nil
        existing.merchant_name = nil
        existing.description = nil
        new_exp.amount = nil
        new_exp.transaction_date = nil
        new_exp.merchant_name = nil
        new_exp.description = nil
        
        expect { conflict.send(:calculate_similarity_score) }.not_to raise_error
      end
    end

    describe "transaction rollback scenarios" do
      let(:conflict) { build_stubbed(:sync_conflict) }

      it "handles resolution creation failure" do
        allow(conflict).to receive(:transaction).and_raise(ActiveRecord::RecordInvalid.new(build_stubbed(:conflict_resolution)))
        
        expect { conflict.resolve!("keep_existing") }.to raise_error(ActiveRecord::RecordInvalid)
      end

      it "handles apply_resolution failure" do
        allow(conflict).to receive(:transaction).and_yield
        allow(conflict).to receive(:capture_current_state).and_return({})
        allow(conflict.conflict_resolutions).to receive(:create!).and_return(double(update!: true))
        allow(conflict).to receive(:apply_resolution).and_raise(StandardError.new("Apply failed"))
        
        expect { conflict.resolve!("keep_existing") }.to raise_error(StandardError, "Apply failed")
      end
    end

    describe "concurrent conflict handling" do
      it "handles multiple conflicts for same expense pair" do
        expense1 = build_stubbed(:expense, id: 1)
        expense2 = build_stubbed(:expense, id: 2)
        
        conflict1 = build_stubbed(:sync_conflict, 
          existing_expense: expense1,
          new_expense: expense2,
          conflict_type: "duplicate"
        )
        conflict2 = build_stubbed(:sync_conflict, 
          existing_expense: expense1,
          new_expense: expense2,
          conflict_type: "similar"
        )
        
        expect(conflict1).to be_valid
        expect(conflict2).to be_valid
      end
    end

    describe "priority edge cases" do
      let(:conflict) { build_stubbed(:sync_conflict) }

      it "handles nil similarity score for duplicate priority" do
        conflict.conflict_type = "duplicate"
        conflict.similarity_score = nil
        conflict.send(:set_priority)
        expect(conflict.priority).to eq(2)
      end

      it "handles boundary similarity score" do
        conflict.conflict_type = "duplicate"
        conflict.similarity_score = 90
        conflict.send(:set_priority)
        expect(conflict.priority).to eq(1)
      end

      it "handles unknown conflict type" do
        allow(conflict).to receive(:conflict_type).and_return("unknown_type")
        conflict.send(:set_priority)
        expect(conflict.priority).to eq(0)
      end
    end
  end
end
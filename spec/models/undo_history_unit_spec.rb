# frozen_string_literal: true

require "rails_helper"

RSpec.describe UndoHistory, type: :model, unit: true do
  describe "constants" do
    it "defines UNDO_WINDOW as 5 minutes" do
      expect(described_class::UNDO_WINDOW).to eq(5.minutes)
    end

    it "defines UNDO_WINDOW in seconds as 300" do
      expect(described_class::UNDO_WINDOW.to_i).to eq(300)
    end
  end

  describe "associations" do
    it { should belong_to(:user) }
  end

  describe "validations" do
    subject do
      build(:undo_history)
    end

    it { should validate_presence_of(:action_type) }
    it { should validate_presence_of(:record_data) }
    it { should validate_presence_of(:undoable_type) }
  end

  describe "scopes" do
    describe ".for_user" do
      let!(:user_a) { create(:user) }
      let!(:user_b) { create(:user) }
      let!(:history_a) { create(:undo_history, user: user_a) }
      let!(:history_b) { create(:undo_history, user: user_b) }

      it "returns records for the given user" do
        expect(UndoHistory.for_user(user_a)).to include(history_a)
        expect(UndoHistory.for_user(user_a)).not_to include(history_b)
      end

      it "excludes records from other users" do
        expect(UndoHistory.for_user(user_b)).to include(history_b)
        expect(UndoHistory.for_user(user_b)).not_to include(history_a)
      end
    end


    describe ".recent" do
      it "includes records created within the undo window (5 minutes)" do
        recent = create(:undo_history, created_at: 4.minutes.ago)
        _old = create(:undo_history, created_at: 6.minutes.ago)

        expect(described_class.recent).to include(recent)
      end

      it "excludes records created outside the 5-minute window" do
        _old = create(:undo_history, created_at: 6.minutes.ago)

        expect(described_class.recent).to be_empty
      end

      it "uses UNDO_WINDOW for the time boundary" do
        boundary_record = create(:undo_history, created_at: (described_class::UNDO_WINDOW - 1.second).ago)

        expect(described_class.recent).to include(boundary_record)
      end
    end

    describe ".pending" do
      it "returns records not yet undone or expired" do
        pending_record = create(:undo_history, undone_at: nil, expired_at: nil)
        _undone = create(:undo_history, undone_at: Time.current)
        _expired = create(:undo_history, expired_at: Time.current)

        expect(described_class.pending).to include(pending_record)
        expect(described_class.pending).not_to include(_undone, _expired)
      end
    end
  end

  describe "#time_remaining" do
    it "returns seconds remaining within the 5-minute window" do
      record = build(:undo_history, expires_at: 4.minutes.from_now)

      expect(record.time_remaining).to be_within(5).of(240)
    end

    it "returns 0 when already undone" do
      record = build(:undo_history, undone_at: Time.current, expires_at: 5.minutes.from_now)

      expect(record.time_remaining).to eq(0)
    end

    it "returns 0 when expired" do
      record = build(:undo_history, expired_at: 1.minute.ago, expires_at: 1.minute.ago)

      expect(record.time_remaining).to eq(0)
    end

    it "returns 0 when expires_at is in the past" do
      record = build(:undo_history, expires_at: 1.second.ago)

      expect(record.time_remaining).to eq(0)
    end

    it "returns approximately 300 for a newly created record" do
      record = build(:undo_history, expires_at: described_class::UNDO_WINDOW.from_now)

      expect(record.time_remaining).to be_within(5).of(300)
    end
  end

  describe "#within_undo_window?" do
    it "returns true when created within 5 minutes" do
      record = build(:undo_history, created_at: 4.minutes.ago)

      expect(record.within_undo_window?).to be true
    end

    it "returns false when created more than 5 minutes ago" do
      record = build(:undo_history, created_at: 6.minutes.ago)

      expect(record.within_undo_window?).to be false
    end

    it "uses UNDO_WINDOW (5 minutes) as boundary, not 30 seconds" do
      # Record created 2 minutes ago should still be within window
      record = build(:undo_history, created_at: 2.minutes.ago)

      expect(record.within_undo_window?).to be true
    end
  end

  describe "#undoable?" do
    it "returns true for a fresh pending record" do
      record = build(:undo_history, created_at: 1.minute.ago, expires_at: 4.minutes.from_now)

      expect(record.undoable?).to be true
    end

    it "returns false when already undone" do
      record = build(:undo_history, undone_at: Time.current, expires_at: 4.minutes.from_now)

      expect(record.undoable?).to be false
    end
  end

  describe "callbacks" do
    describe "#set_expiration" do
      it "sets expires_at to UNDO_WINDOW (5 minutes) from now on create" do
        record = create(:undo_history)

        expect(record.expires_at).to be_within(5.seconds).of(5.minutes.from_now)
      end

      it "does not override an already-set expires_at" do
        custom_expiry = 10.minutes.from_now
        record = create(:undo_history, expires_at: custom_expiry)

        expect(record.expires_at).to be_within(1.second).of(custom_expiry)
      end
    end
  end

  describe "enums" do
    it "defines soft_delete action type" do
      expect(described_class.action_types).to include("soft_delete")
    end

    it "defines bulk_delete action type" do
      expect(described_class.action_types).to include("bulk_delete")
    end
  end
end

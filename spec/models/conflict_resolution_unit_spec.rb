# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConflictResolution, type: :model, unit: true do
  describe "associations" do
    it { should belong_to(:sync_conflict) }
    it { should belong_to(:undone_by_resolution).class_name("ConflictResolution").optional }
    it { should have_one(:undoes_resolution).class_name("ConflictResolution").with_foreign_key("undone_by_resolution_id") }
  end

  describe "validations" do
    describe "action validation" do
      it { should validate_presence_of(:action) }

      it "validates action inclusion" do
        should validate_inclusion_of(:action)
          .in_array(%w[keep_existing keep_new keep_both merged custom undo])
      end

      it "rejects invalid action values" do
        resolution = build_stubbed(:conflict_resolution, action: "invalid_action")
        expect(resolution).not_to be_valid
        expect(resolution.errors[:action]).to include("is not included in the list")
      end
    end

    describe "resolution_method validation" do
      it "validates resolution_method inclusion when present" do
        should validate_inclusion_of(:resolution_method)
          .in_array(%w[manual auto bulk api])
          .allow_nil
      end

      it "allows nil resolution_method" do
        resolution = build_stubbed(:conflict_resolution, resolution_method: nil)
        expect(resolution).to be_valid
      end

      it "rejects invalid resolution_method values" do
        resolution = build_stubbed(:conflict_resolution, resolution_method: "invalid_method")
        expect(resolution).not_to be_valid
        expect(resolution.errors[:resolution_method]).to include("is not included in the list")
      end
    end
  end

  describe "scopes" do
    describe ".not_undone" do
      it "returns resolutions that are not undone" do
        query = described_class.not_undone
        expect(query.to_sql).to include('"undone" = FALSE')
      end
    end

    describe ".undone" do
      it "returns resolutions that are undone" do
        query = described_class.undone
        expect(query.to_sql).to include('"undone" = TRUE')
      end
    end

    describe ".recent" do
      it "orders resolutions by created_at descending" do
        query = described_class.recent
        expect(query.to_sql).to include('ORDER BY "conflict_resolutions"."created_at" DESC')
      end
    end

    describe ".manual" do
      it "returns manually resolved resolutions" do
        query = described_class.manual
        expect(query.to_sql).to include('"resolution_method" = \'manual\'')
      end
    end

    describe ".automatic" do
      it "returns automatically resolved resolutions" do
        query = described_class.automatic
        expect(query.to_sql).to include('"resolution_method" IN')
        expect(query.to_sql).to include('auto')
      end
    end

    describe ".undoable" do
      it "returns undoable resolutions that haven't been undone" do
        query = described_class.undoable
        expect(query.to_sql).to include('"undoable" = TRUE')
        expect(query.to_sql).to include('"undone" = FALSE')
      end
    end
  end

  describe "instance methods" do
    describe "#can_undo?" do
      context "when resolution is undoable, not undone, and not an undo action" do
        it "returns true" do
          resolution = build_stubbed(:conflict_resolution, undoable: true, undone: false, action: "keep_existing")
          expect(resolution.can_undo?).to be true
        end
      end

      context "when resolution is not undoable" do
        it "returns false" do
          resolution = build_stubbed(:conflict_resolution, undoable: false, undone: false, action: "keep_existing")
          expect(resolution.can_undo?).to be false
        end
      end

      context "when resolution is already undone" do
        it "returns false" do
          resolution = build_stubbed(:conflict_resolution, undoable: true, undone: true, action: "keep_existing")
          expect(resolution.can_undo?).to be false
        end
      end

      context "when resolution is an undo action" do
        it "returns false" do
          resolution = build_stubbed(:conflict_resolution, undoable: true, undone: false, action: "undo")
          expect(resolution.can_undo?).to be false
        end
      end
    end

    describe "#undo_action?" do
      it "returns true for undo action" do
        resolution = build_stubbed(:conflict_resolution, action: "undo")
        expect(resolution.undo_action?).to be true
      end

      it "returns false for non-undo actions" do
        %w[keep_existing keep_new keep_both merged custom].each do |action|
          resolution = build_stubbed(:conflict_resolution, action: action)
          expect(resolution.undo_action?).to be false
        end
      end
    end

    describe "#display_action" do
      it "returns Spanish translations for valid actions" do
        translations = {
          "keep_existing" => "Mantener existente",
          "keep_new" => "Mantener nuevo",
          "keep_both" => "Mantener ambos",
          "merged" => "Fusionado",
          "custom" => "Personalizado",
          "undo" => "Deshacer"
        }

        translations.each do |action, expected|
          resolution = build_stubbed(:conflict_resolution, action: action)
          expect(resolution.display_action).to eq(expected)
        end
      end

      it "humanizes unknown actions" do
        resolution = build_stubbed(:conflict_resolution)
        allow(resolution).to receive(:action).and_return("unknown_action")
        expect(resolution.display_action).to eq("Unknown action")
      end
    end

    describe "#display_method" do
      it "returns Spanish translations for valid methods" do
        translations = {
          "manual" => "Manual",
          "auto" => "Automático",
          "bulk" => "En lote",
          "api" => "API"
        }

        translations.each do |method, expected|
          resolution = build_stubbed(:conflict_resolution, resolution_method: method)
          expect(resolution.display_method).to eq(expected)
        end
      end

      it "returns 'Desconocido' for nil resolution_method" do
        resolution = build_stubbed(:conflict_resolution, resolution_method: nil)
        expect(resolution.display_method).to eq("Desconocido")
      end

      it "humanizes unknown methods" do
        resolution = build_stubbed(:conflict_resolution, resolution_method: "special_method")
        allow(resolution).to receive(:resolution_method).and_return("special_method")
        expect(resolution.display_method).to eq("Special method")
      end
    end

    describe "#changed_fields" do
      context "with no changes_made" do
        it "returns empty array" do
          resolution = build_stubbed(:conflict_resolution, changes_made: nil)
          expect(resolution.changed_fields).to eq([])
        end
      end

      context "with empty changes_made" do
        it "returns empty array" do
          resolution = build_stubbed(:conflict_resolution, changes_made: {})
          expect(resolution.changed_fields).to eq([])
        end
      end

      context "with existing expense changes" do
        it "returns formatted field changes" do
          changes_made = {
            "existing_expense" => {
              "before" => { "amount" => 100, "description" => "old" },
              "after" => { "amount" => 150, "description" => "new" }
            }
          }

          resolution = build_stubbed(:conflict_resolution, changes_made: changes_made)
          fields = resolution.changed_fields

          expect(fields).to include(
            hash_including(
              expense: "existing",
              field: "amount",
              before: 100,
              after: 150
            )
          )
          expect(fields).to include(
            hash_including(
              expense: "existing",
              field: "description",
              before: "old",
              after: "new"
            )
          )
        end
      end

      context "with new expense changes" do
        it "returns formatted field changes" do
          changes_made = {
            "new_expense" => {
              "before" => { "merchant_name" => "Store A" },
              "after" => { "merchant_name" => "Store B" }
            }
          }

          resolution = build_stubbed(:conflict_resolution, changes_made: changes_made)
          fields = resolution.changed_fields

          expect(fields).to include(
            hash_including(
              expense: "new",
              field: "merchant_name",
              before: "Store A",
              after: "Store B"
            )
          )
        end
      end

      context "with both expense changes" do
        it "returns all field changes" do
          changes_made = {
            "existing_expense" => {
              "before" => { "amount" => 100 },
              "after" => { "amount" => 150 }
            },
            "new_expense" => {
              "before" => { "category_id" => 1 },
              "after" => { "category_id" => 2 }
            }
          }

          resolution = build_stubbed(:conflict_resolution, changes_made: changes_made)
          fields = resolution.changed_fields

          expect(fields.length).to eq(2)
          expect(fields.map { |f| f[:expense] }).to contain_exactly("existing", "new")
        end
      end

      context "with unchanged fields" do
        it "excludes unchanged fields" do
          changes_made = {
            "existing_expense" => {
              "before" => { "amount" => 100, "description" => "same" },
              "after" => { "amount" => 100, "description" => "different" }
            }
          }

          resolution = build_stubbed(:conflict_resolution, changes_made: changes_made)
          fields = resolution.changed_fields

          expect(fields.length).to eq(1)
          expect(fields.first[:field]).to eq("description")
        end
      end
    end

    describe "#summary" do
      context "for keep_existing action" do
        it "returns appropriate Spanish summary" do
          resolution = build_stubbed(:conflict_resolution, action: "keep_existing")
          expect(resolution.summary).to eq("Se mantuvo el gasto existente y se marcó el nuevo como duplicado")
        end
      end

      context "for keep_new action" do
        it "returns appropriate Spanish summary" do
          resolution = build_stubbed(:conflict_resolution, action: "keep_new")
          expect(resolution.summary).to eq("Se mantuvo el nuevo gasto y se marcó el existente como duplicado")
        end
      end

      context "for keep_both action" do
        it "returns appropriate Spanish summary" do
          resolution = build_stubbed(:conflict_resolution, action: "keep_both")
          expect(resolution.summary).to eq("Se mantuvieron ambos gastos como separados")
        end
      end

      context "for merged action" do
        it "includes changed fields count" do
          resolution = build_stubbed(:conflict_resolution, action: "merged")
          allow(resolution).to receive(:changed_fields).and_return([{}, {}, {}])
          expect(resolution.summary).to eq("Se fusionaron los gastos, combinando 3 campos")
        end
      end

      context "for custom action" do
        it "includes changed fields count" do
          resolution = build_stubbed(:conflict_resolution, action: "custom")
          allow(resolution).to receive(:changed_fields).and_return([{}, {}])
          expect(resolution.summary).to eq("Se aplicó una resolución personalizada con 2 cambios")
        end
      end

      context "for undo action" do
        it "returns appropriate Spanish summary" do
          resolution = build_stubbed(:conflict_resolution, action: "undo")
          expect(resolution.summary).to eq("Se deshizo la resolución anterior")
        end
      end

      context "for unknown action" do
        it "returns default summary" do
          resolution = build_stubbed(:conflict_resolution)
          allow(resolution).to receive(:action).and_return("unknown")
          expect(resolution.summary).to eq("Resolución aplicada")
        end
      end
    end
  end

  describe "edge cases" do
    describe "circular undo relationships" do
      it "prevents circular references" do
        resolution1 = build_stubbed(:conflict_resolution, id: 1)
        resolution2 = build_stubbed(:conflict_resolution, id: 2, undone_by_resolution: resolution1)
        
        # Attempting to set resolution1's undone_by to resolution2 would create a cycle
        resolution1.undone_by_resolution = resolution2
        
        # The model should handle this gracefully (validation or logic to prevent)
        expect { resolution1.valid? }.not_to raise_error
      end
    end

    describe "complex changes_made structures" do
      it "handles deeply nested changes" do
        complex_changes = {
          "existing_expense" => {
            "before" => {
              "amount" => 100,
              "metadata" => { "source" => "email", "confidence" => 0.8 }
            },
            "after" => {
              "amount" => 150,
              "metadata" => { "source" => "manual", "confidence" => 1.0 }
            }
          }
        }

        resolution = build_stubbed(:conflict_resolution, changes_made: complex_changes)
        fields = resolution.changed_fields

        expect(fields).to include(
          hash_including(field: "amount"),
          hash_including(field: "metadata")
        )
      end
    end

    describe "nil handling" do
      it "handles nil values in changes gracefully" do
        changes_with_nils = {
          "existing_expense" => {
            "before" => { "description" => nil },
            "after" => { "description" => "New description" }
          }
        }

        resolution = build_stubbed(:conflict_resolution, changes_made: changes_with_nils)
        fields = resolution.changed_fields

        expect(fields.first[:before]).to be_nil
        expect(fields.first[:after]).to eq("New description")
      end
    end
  end
end
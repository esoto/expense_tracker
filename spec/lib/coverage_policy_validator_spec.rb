# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/coverage_policy_validator")

RSpec.describe CoveragePolicyValidator, unit: true do
  subject(:validator) { described_class.new(Rails.root.join("config/coverage_policy.yml").to_s) }

  describe "#load_coverage_data" do
    let(:resultset_path) { "coverage/integration/.resultset.json" }

    def stub_resultset(resultset)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(resultset_path).and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(resultset_path).and_return(resultset.to_json)
    end

    def load_data
      validator.send(:load_coverage_data, "integration")
    end

    it "returns a single serial entry's lines unchanged" do
      stub_resultset(
        "integration-tests-100" => {
          "timestamp" => 100,
          "coverage" => { "app/models/expense.rb" => { "lines" => [ 1, 0, nil, 2 ] } }
        }
      )

      expect(load_data).to eq("app/models/expense.rb" => [ 1, 0, nil, 2 ])
    end

    it "merges parallel worker entries by summing per-line hit counts" do
      stub_resultset(
        "integration-tests-100" => {
          "timestamp" => 100,
          "coverage" => { "app/models/expense.rb" => { "lines" => [ 1, 0, nil, 2 ] } }
        },
        "integration-tests2-100" => {
          "timestamp" => 103,
          "coverage" => { "app/models/expense.rb" => { "lines" => [ 0, 3, nil, 0 ] } }
        }
      )

      expect(load_data).to eq("app/models/expense.rb" => [ 1, 3, nil, 2 ])
    end

    it "keeps nil for lines not relevant in any entry" do
      stub_resultset(
        "integration-tests-100" => {
          "timestamp" => 100,
          "coverage" => { "app/models/expense.rb" => { "lines" => [ nil, 1 ] } }
        },
        "integration-tests2-100" => {
          "timestamp" => 101,
          "coverage" => { "app/models/expense.rb" => { "lines" => [ nil, 0 ] } }
        }
      )

      expect(load_data).to eq("app/models/expense.rb" => [ nil, 1 ])
    end

    it "resolves relevance disagreement as not-relevant (nil-wins)" do
      # On SimpleCov <= 0.22, a worker that never loaded a tracked file gets
      # its coverage fabricated by LinesClassifier — a regex line scanner
      # (see simplecov-ruby/simplecov#654) that can't tell multi-line
      # literals or bare `when`/`else`/`end` from real statements, roughly
      # doubling the file's apparent line count with all-zero fabricated
      # hits. nil-wins discards those fabricated stubs in favor of a worker
      # that actually ran the file; an inclusive rule would union the
      # fabricated lines in and understate coverage instead.
      stub_resultset(
        "integration-tests-100" => {
          "timestamp" => 100,
          "coverage" => { "app/models/expense.rb" => { "lines" => [ 0, 0 ] } }
        },
        "integration-tests2-100" => {
          "timestamp" => 101,
          "coverage" => { "app/models/expense.rb" => { "lines" => [ nil, 5 ] } }
        }
      )

      expect(load_data).to eq("app/models/expense.rb" => [ nil, 5 ])
    end

    it "treats a line as covered when only one worker exercised it" do
      stub_resultset(
        "integration-tests-100" => {
          "timestamp" => 100,
          "coverage" => { "app/models/expense.rb" => { "lines" => [ nil, nil ] } }
        },
        "integration-tests2-100" => {
          "timestamp" => 101,
          "coverage" => { "app/models/expense.rb" => { "lines" => [ nil, 4 ] } }
        }
      )

      expect(load_data).to eq("app/models/expense.rb" => [ nil, 4 ])
    end

    it "excludes entries older than the same-run window" do
      stale = described_class::SAME_RUN_WINDOW_SECONDS + 1
      stub_resultset(
        "integration-tests-old" => {
          "timestamp" => 5_000,
          "coverage" => { "app/models/stale.rb" => { "lines" => [ 9, 9 ] } }
        },
        "integration-tests-new" => {
          "timestamp" => 5_000 + stale,
          "coverage" => { "app/models/expense.rb" => { "lines" => [ 1, 0 ] } }
        }
      )

      expect(load_data).to eq("app/models/expense.rb" => [ 1, 0 ])
    end

    it "merges files unique to a single worker" do
      stub_resultset(
        "integration-tests-100" => {
          "timestamp" => 100,
          "coverage" => { "app/models/expense.rb" => { "lines" => [ 1 ] } }
        },
        "integration-tests2-100" => {
          "timestamp" => 101,
          "coverage" => { "app/services/sync.rb" => { "lines" => [ 2 ] } }
        }
      )

      expect(load_data).to eq(
        "app/models/expense.rb" => [ 1 ],
        "app/services/sync.rb" => [ 2 ]
      )
    end

    it "handles the old SimpleCov array format" do
      stub_resultset(
        "integration-tests-100" => {
          "timestamp" => 100,
          "coverage" => { "app/models/expense.rb" => [ 1, nil, 0 ] }
        }
      )

      expect(load_data).to eq("app/models/expense.rb" => [ 1, nil, 0 ])
    end

    it "returns nil when the resultset is missing" do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(resultset_path).and_return(false)

      expect(load_data).to be_nil
    end

    it "returns nil on malformed JSON" do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(resultset_path).and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(resultset_path).and_return("{not json")

      expect(load_data).to be_nil
    end
  end
end

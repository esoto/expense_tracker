# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Engine, "thread pool management", :unit, type: :model do
  describe ".shared_thread_pool" do
    it "returns a Concurrent::ThreadPoolExecutor" do
      pool = described_class.shared_thread_pool
      expect(pool).to be_a(Concurrent::ThreadPoolExecutor)
    end

    it "returns the same instance across multiple calls" do
      pool1 = described_class.shared_thread_pool
      pool2 = described_class.shared_thread_pool
      expect(pool1).to equal(pool2)
    end

    it "returns the same pool for different engine instances" do
      engine1 = described_class.new
      engine2 = described_class.new
      expect(engine1.instance_variable_get(:@thread_pool)).to equal(engine2.instance_variable_get(:@thread_pool))
    end
  end

  describe "thread pool configuration" do
    it "has a minimum of 2 threads" do
      pool = described_class.shared_thread_pool
      expect(pool.min_length).to eq(2)
    end

    it "has a maximum of MAX_CONCURRENT_OPERATIONS threads" do
      pool = described_class.shared_thread_pool
      expect(pool.max_length).to eq(described_class::MAX_CONCURRENT_OPERATIONS)
    end

    it "uses caller_runs fallback policy" do
      pool = described_class.shared_thread_pool
      expect(pool.fallback_policy).to eq(:caller_runs)
    end
  end

  describe "instance shutdown! does not kill shared pool" do
    it "keeps the shared pool running after engine shutdown" do
      engine = described_class.new
      pool = described_class.shared_thread_pool

      engine.shutdown!

      expect(pool.running?).to be true
    end

    it "allows new engine instances to use the pool after another shuts down" do
      engine1 = described_class.new
      engine1.shutdown!

      engine2 = described_class.new
      pool = engine2.instance_variable_get(:@thread_pool)
      expect(pool.running?).to be true
    end
  end
end

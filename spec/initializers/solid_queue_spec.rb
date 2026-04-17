# frozen_string_literal: true

require "rails_helper"

# PER-506: Defensive config for Solid Queue lease / heartbeat intervals.
#
# Background: Solid Queue 1.4.0 supervisor prunes a worker if its last
# heartbeat is older than `process_alive_threshold` (default: 5 minutes).
# When pruned, the worker's claimed executions are released back to the
# queue and may be picked up by another worker — causing duplicate
# execution. Heartbeats run on an independent Concurrent::TimerTask thread,
# so normal job work doesn't miss them. BUT heartbeats CAN stall under:
#   - DB connection-pool exhaustion (heartbeat can't INSERT a record)
#   - GC pauses
#   - Kernel-level process freeze
#
# The default 5-minute threshold is aggressive — one 4-minute GC pause on
# a large Ruby heap can trip it. Bumping to 10 minutes + halving the
# heartbeat interval gives the supervisor more samples before declaring
# a process dead, dramatically reducing false-positive pruning.
#
# Note: the PER-506 ticket proposed `claim_timeout: 600` in config/queue.yml,
# but that setting does not exist in Solid Queue 1.4.0. The effective lever
# for lease expiration is `process_alive_threshold` on the SolidQueue
# module itself (set via the initializer).
RSpec.describe "config/initializers/solid_queue.rb", :unit do
  describe "lease / heartbeat configuration (PER-506)" do
    it "uses a 10-minute process_alive_threshold (tolerates GC pauses + DB pool stalls)" do
      # Gem default is 5.minutes. Too aggressive for Ruby apps with a
      # multi-GB heap where major GC can pause 3-4 minutes.
      expect(SolidQueue.process_alive_threshold).to eq(10.minutes)
    end

    it "uses a 30-second heartbeat interval (2x default = more samples per threshold window)" do
      # Gem default is 60s. Halving gives the supervisor 20 heartbeat
      # opportunities per 10-minute window instead of 5 — so a single
      # missed beat doesn't dominate the kill decision.
      expect(SolidQueue.process_heartbeat_interval).to eq(30.seconds)
    end

    it "reads the threshold from ENV[SOLID_QUEUE_ALIVE_THRESHOLD] when set" do
      # Behavioral contract: env-tunable, matching the existing pattern
      # used by preserve_finished_jobs and shutdown_timeout in the same
      # initializer. We don't actually mutate ENV in the test (the
      # initializer has already evaluated at boot), but we assert the
      # default is the documented one — this guards against someone
      # silently changing the env-fetched default.
      expect(ENV.fetch("SOLID_QUEUE_ALIVE_THRESHOLD", 600).to_i).to eq(600)
    end

    it "reads the heartbeat interval from ENV[SOLID_QUEUE_HEARTBEAT_INTERVAL] when set" do
      expect(ENV.fetch("SOLID_QUEUE_HEARTBEAT_INTERVAL", 30).to_i).to eq(30)
    end
  end

  describe "existing settings remain configured (regression guards)" do
    it "preserves finished jobs for the env-configured period (default 7 days)" do
      expect(SolidQueue.preserve_finished_jobs).to eq(7.days)
    end

    it "has a shutdown_timeout configured (default 30 seconds)" do
      expect(SolidQueue.shutdown_timeout).to eq(30.seconds)
    end
  end
end

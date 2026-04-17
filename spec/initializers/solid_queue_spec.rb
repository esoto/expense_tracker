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

    # Env-override behavior is NOT unit-testable without reloading the
    # initializer under a stubbed ENV (initializers evaluate once at boot).
    # The two `SolidQueue.X` assertions above prove the initializer wrote
    # the expected default values through; the env contract is documented
    # in the initializer comments + commit message.
  end

  describe "existing settings remain configured (regression guards)" do
    it "preserves finished jobs for the env-configured period (default 7 days)" do
      expect(SolidQueue.preserve_finished_jobs).to eq(7.days)
    end

    it "has a shutdown_timeout configured (default 30 seconds)" do
      expect(SolidQueue.shutdown_timeout).to eq(30.seconds)
    end
  end

  describe "prune / claim-release observability (PER-506)" do
    # Without these subscriptions, the only signal that a worker was
    # falsely pruned (or genuinely died) is via the eventual `discard` when
    # the re-claimed job later fails — too late for ops to correlate.
    it "logs a warning when the supervisor prunes dead processes" do
      expect(Rails.logger).to receive(:warn).with(/Pruned 3 dead process/)
      ActiveSupport::Notifications.instrument("prune_processes.solid_queue", size: 3)
    end

    it "silently no-ops a prune_processes event with size=0" do
      expect(Rails.logger).not_to receive(:warn)
      ActiveSupport::Notifications.instrument("prune_processes.solid_queue", size: 0)
    end

    it "logs a warning when claimed executions get released from dead workers" do
      expect(Rails.logger).to receive(:warn).with(/Released 2 claimed job\(s\) from pruned/)
      ActiveSupport::Notifications.instrument("release_many_claimed.solid_queue", size: 2)
    end

    it "silently no-ops a release_many_claimed event with size=0" do
      expect(Rails.logger).not_to receive(:warn)
      ActiveSupport::Notifications.instrument("release_many_claimed.solid_queue", size: 0)
    end
  end
end

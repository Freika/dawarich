# frozen_string_literal: true

module Visits
  # Entry seam for visit detection: plan-window clamping and the cheap
  # existence guard live here; the pipeline itself is
  # Visits::Detection::Runner. Serialization against concurrent runs happens
  # inside Visits::Detection::Persister's write transaction — compute and
  # geocoder I/O deliberately run unlocked. There is no fallback detector —
  # a failing run raises to Visits::Suggest, which owns user-facing error
  # handling.
  class SmartDetect
    attr_reader :user, :start_at, :end_at

    def initialize(user, start_at:, end_at:)
      @user = user
      @start_at = clamp_to_plan_window(start_at.to_i)
      @end_at = end_at.to_i
    end

    DEADLOCK_ATTEMPTS = 3
    DEADLOCK_PAUSE_SECONDS = 1.0..2.0

    def call
      return [] if @start_at >= @end_at
      return [] unless points_exist?

      with_deadlock_retry do
        runner = Visits::Detection::Runner.new(user, start_at: @start_at, end_at: @end_at)
        visits = runner.call
        @skipped_ranges = runner.skipped_ranges
        visits
      end
    end

    # Batches the Runner refused (over the candidate-point cap) — callers
    # doing whole-history work must not report those as cleanly re-detected.
    def skipped_ranges
      @skipped_ranges || []
    end

    private

    # An import for the same user can deadlock with detection on the
    # invalidation triggers. The Persister writes a window in one transaction
    # and re-running converges, so the loser can simply run again.
    # ponytail: retries absorb a transient lock cycle; a shared lock order
    # between imports and detection would remove the cycle itself.
    def with_deadlock_retry
      attempts = 0
      begin
        yield
      rescue ActiveRecord::Deadlocked => e
        attempts += 1
        raise if attempts >= DEADLOCK_ATTEMPTS

        Rails.logger.warn(
          "[Visits::SmartDetect deadlock_retry] user_id=#{user.id} range=#{@start_at}..#{@end_at} " \
          "attempt=#{attempts} message=#{e.message.lines.first&.strip}"
        )
        sleep(rand(DEADLOCK_PAUSE_SECONDS) * attempts)
        retry
      end
    end

    def clamp_to_plan_window(timestamp)
      window_start = user.data_window_start
      window_start ? [timestamp, window_start.to_i].max : timestamp
    end

    # Detection is stateless over raw points, so ownership by an existing
    # visit is no reason to skip a run.
    def points_exist?
      Point.where(user_id: user.id)
           .not_anomaly
           .where(timestamp: @start_at..@end_at)
           .exists?
    end
  end
end

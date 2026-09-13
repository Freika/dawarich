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

    def call
      return [] if @start_at >= @end_at
      return [] unless points_exist?

      runner = Visits::Detection::Runner.new(user, start_at: @start_at, end_at: @end_at)
      visits = runner.call
      @skipped_ranges = runner.skipped_ranges
      visits
    end

    # Batches the Runner refused (over the candidate-point cap) — callers
    # doing whole-history work must not report those as cleanly re-detected.
    def skipped_ranges
      @skipped_ranges || []
    end

    private

    def clamp_to_plan_window(timestamp)
      return timestamp unless user.respond_to?(:plan_restricted?) && user.plan_restricted?

      [timestamp, user.data_window_start.to_i].max
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

# frozen_string_literal: true

module Tracks
  class OrphanRuns
    def initialize(user, orphans)
      @user = user
      @orphans = orphans
    end

    def call
      return [] if @orphans.empty?

      owned = owned_points
      @orphans.slice_when { |a, b| owned_between?(owned, a.timestamp, b.timestamp) }
              .reject { |run| enclosed?(owned, run) }
    end

    private

    def owned_points
      window = @user.safe_settings.minutes_between_routes.to_i.minutes.to_i
      Point.where(user_id: @user.id)
           .recorded_by(@orphans.first.tracker_id)
           .where.not(track_id: nil)
           .where(timestamp: (@orphans.first.timestamp - window)..(@orphans.last.timestamp + window))
           .order(:timestamp)
           .pluck(:timestamp, :track_id)
    end

    def owned_between?(owned, from, to)
      index = owned.bsearch_index { |timestamp, _| timestamp > from }
      index.present? && owned[index][0] < to
    end

    def enclosed?(owned, run)
      after = owned.bsearch_index { |timestamp, _| timestamp > run.last.timestamp }
      before = (owned.bsearch_index { |timestamp, _| timestamp >= run.first.timestamp } || owned.size) - 1
      after.present? && before >= 0 && owned[before][1] == owned[after][1]
    end
  end
end

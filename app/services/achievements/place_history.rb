# frozen_string_literal: true

module Achievements
  class PlaceHistory
    Interval = Data.define(:from, :to, :ids)
    MIN_STAY = 20.minutes

    def initialize(selection)
      @selection = selection
    end

    def call
      visits = @selection.user.visits.active.where(place_id: @selection.place_id)
                         .where('duration >= ? AND ended_at <= ?', MIN_STAY.to_i, Time.current)
                         .where('status = ? OR confidence >= 70', Visit.statuses.fetch('confirmed'))
                         .order(:started_at, :id)
      visits.each_with_object([]) do |visit, intervals|
        next if visit.ended_at - visit.started_at < MIN_STAY

        if intervals.last && visit.started_at <= intervals.last.to
          old = intervals.pop
          intervals << Interval.new(from: old.from, to: [old.to, visit.ended_at].max, ids: old.ids + [visit.id])
        else
          intervals << Interval.new(from: visit.started_at, to: visit.ended_at, ids: [visit.id])
        end
      end
    end
  end
end

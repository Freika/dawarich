# frozen_string_literal: true

module Achievements
  class SeasonsRule
    # State dominance: for each season mask retain the earliest possible last
    # visit. A later ending path can never admit more future visits.
    def self.call(intervals, timezone:)
      states = { 0 => { date: nil, visits: [] } }
      intervals.each do |interval|
        date = interval.from.in_time_zone(timezone).to_date
        season = (date.month % 12) / 3
        bit = 1 << season
        states.to_a.each do |mask, state|
          next unless (mask & bit).zero?
          next if state[:date] && date - state[:date] < 7

          states[mask | bit] ||= { date: date, visits: state[:visits] + [interval] }
        end
      end
      mask, state = states.max_by { |key, value| [key.digits(2).sum, -(value[:date]&.jd || 0)] }
      evidence = state[:visits].map do |visit|
        { 'season' => (visit.from.in_time_zone(timezone).month % 12) / 3,
          'visit_ids' => visit.ids, 'at' => visit.from.iso8601 }
      end
      levels = mask == 15 ? { '1' => (state[:visits].last.from + PlaceHistory::MIN_STAY).iso8601 } : {}
      { 'progress' => evidence.size, 'target' => 4, 'season_mask' => mask,
        'levels' => levels, 'evidence' => evidence }
    end
  end
end

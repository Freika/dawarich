# frozen_string_literal: true

module Achievements
  class ReturnRule
    YEARS = [1, 3, 5].freeze

    def self.call(intervals, timezone:)
      levels = {}
      evidence = []
      intervals.each_cons(2) do |previous, current|
        from = previous.to.in_time_zone(timezone)
        to = current.from.in_time_zone(timezone)
        YEARS.each_with_index do |years, index|
          next if to < from.advance(years: years) || levels.key?((index + 1).to_s)

          levels[(index + 1).to_s] = (current.from + PlaceHistory::MIN_STAY).iso8601
          evidence = [{ 'visit_ids' => previous.ids, 'at' => previous.to.iso8601 },
                      { 'visit_ids' => current.ids, 'at' => current.from.iso8601 }]
        end
      end
      { 'progress' => levels.empty? ? 0 : 1, 'target' => 1, 'levels' => levels,
        'evidence' => evidence, 'last_visit' => intervals.last&.from&.iso8601 }
    end
  end
end

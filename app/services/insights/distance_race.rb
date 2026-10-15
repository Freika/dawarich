# frozen_string_literal: true

module Insights
  class DistanceRace
    Result = Data.define(:year, :current, :previous, :lead)

    def self.for(user, year)
      stats = user.scoped_stats.where(month: 1..12)
      today = Time.current.in_time_zone(user.timezone_iana).to_date

      new(stats.where(year:), stats.where(year: year - 1), year, today:).call
    end

    def initialize(current_stats, previous_stats, year, today:)
      @current_stats = current_stats
      @previous_stats = previous_stats
      @year = year
      @today = today
    end

    def call
      last_index = @year == @today.year ? @today.yday - 1 : year_length(@year) - 1
      return if @year > @today.year || last_index.negative?

      current = cumulative(@year, DailyDistances.call(@current_stats), last_index)
      previous_daily = DailyDistances.call(@previous_stats)
      previous = cumulative(@year - 1, previous_daily, year_length(@year - 1) - 1) if previous_daily.any?

      Result.new(year: @year, current:, previous:,
                 lead: previous && (current.last - previous[[last_index, previous.size - 1].min]))
    end

    private

    def cumulative(year, daily, last_index)
      start = Date.new(year, 1, 1)
      total = 0
      (0..last_index).map { |offset| total += daily.fetch((start + offset).strftime('%Y-%m-%d'), 0) }
    end

    def year_length(year)
      Date.new(year, 12, 31).yday
    end
  end
end

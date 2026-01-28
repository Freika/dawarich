# frozen_string_literal: true

module Insights
  class TravelPatternsLoader
    Result = Struct.new(
      :time_of_day,
      :day_of_week,
      :seasonality,
      :activity_breakdown,
      keyword_init: true
    )

    def initialize(user, year, month, monthly_digest: nil)
      @user = user
      @year = year
      @month = month
      @monthly_digest = monthly_digest
    end

    def call
      Result.new(
        time_of_day: load_time_of_day,
        day_of_week: load_day_of_week,
        seasonality: load_seasonality,
        activity_breakdown: load_activity_breakdown
      )
    end

    private

    attr_reader :user, :year, :month, :monthly_digest

    def load_time_of_day
      monthly_digest&.time_of_day_distribution.presence ||
        Stats::TimeOfDayQuery.new(user, year, month, user.timezone).call
    end

    def load_day_of_week
      monthly_digest&.weekly_pattern.presence || Array.new(7, 0)
    end

    def load_seasonality
      yearly_digest = user.digests.yearly.find_by(year: year)
      yearly_digest&.seasonality.presence ||
        Users::Digests::SeasonalityCalculator.new(user, year).call
    end

    def load_activity_breakdown
      monthly_digest&.activity_breakdown.presence ||
        Users::Digests::ActivityBreakdownCalculator.new(user, year, month).call
    end
  end
end

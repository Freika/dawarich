# frozen_string_literal: true

module Insights
  # Distance per weekday across a year, summed from the monthly digests.
  class WeeklyDistanceTotals
    def initialize(user, year)
      @user = user
      @year = year
    end

    def call
      digests = @user.digests.monthly.where(year: @year).select(:id, :year, :month, :monthly_distances)

      digests.each_with_object(Array.new(7, 0)) do |digest, weekly_totals|
        pattern = digest.weekly_pattern
        next unless pattern.is_a?(Array) && pattern.size == 7

        pattern.each_with_index { |distance, index| weekly_totals[index] += distance.to_i }
      end
    end
  end
end

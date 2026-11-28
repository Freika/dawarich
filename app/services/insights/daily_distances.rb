# frozen_string_literal: true

module Insights
  module DailyDistances
    module_function

    def call(stats)
      stats.each_with_object({}) do |stat, daily|
        next unless stat.daily_distance.is_a?(Hash) || stat.daily_distance.is_a?(Array)

        stat.daily_distance.to_h.each do |day_number, distance|
          date = Date.new(stat.year, stat.month, day_number.to_i)
          key = date.strftime('%Y-%m-%d')
          daily[key] = daily.fetch(key, 0) + distance.to_i
        rescue ArgumentError
          next
        end
      end
    end
  end
end

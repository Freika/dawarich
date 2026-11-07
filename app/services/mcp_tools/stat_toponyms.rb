# frozen_string_literal: true

module McpTools
  # Adds up the countries and cities stored on monthly stats, keyed by country
  # name and then city name, with the minutes and points summed across months.
  module StatToponyms
    module_function

    def countries(stats)
      stats.each_with_object({}) do |stat, countries|
        stat.toponyms.each do |toponym|
          next if toponym['country'].blank?

          cities = countries[toponym['country']] ||= {}
          toponym['cities'].each do |city|
            totals = cities[city['city']] ||= { minutes: 0, points: 0 }
            totals[:minutes] += city['stayed_for'].to_i
            totals[:points] += city['points'].to_i
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module Stats
  class Toponyms
    def initialize(points, min_minutes_spent_in_city:)
      @points = points
      @minimum = min_minutes_spent_in_city
      @countries = {}
      @flight_points = 0
    end

    def call
      @country_names = Country.pluck(:id, :name).to_h
      @points.each { |point| consume(point) }
      finish_run
      @countries.map do |country, cities|
        values = cities.filter_map do |city, totals|
          duration = totals[:seconds] / 60
          next if duration < @minimum

          CountriesAndCities::CityData.new(city: city, points: totals[:points],
                                           timestamp: totals[:timestamp], stayed_for: duration)
        end
        CountriesAndCities::CountryData.new(country: country, cities: values)
      end
    end

    private

    def consume(point)
      if point[:velocity].to_f * CountriesAndCities::MS_TO_KMH > CountriesAndCities::FLYOVER_VELOCITY_THRESHOLD_KMH
        @flight_points += 1
        finish_run if @flight_points == CountriesAndCities::MIN_TRANSIT_RUN_POINTS
        return
      end

      @flight_points = 0
      return if point[:country_name].nil? || point[:city].nil?

      country = @country_names[point[:country_id]] || point[:country_name]
      timestamp = point[:timestamp]
      if @run && (@run[:country] != country || @run[:city] != point[:city] ||
                  timestamp - @run[:last] > CountriesAndCities::BRIDGE_CAP_SECONDS)
        finish_run
      end
      @run ||= { country: country, city: point[:city], first: timestamp, last: timestamp, points: 0 }
      @run[:last] = timestamp
      @run[:points] += 1
    end

    def finish_run
      return unless @run

      cities = (@countries[@run[:country]] ||= {})
      totals = (cities[@run[:city]] ||= { seconds: 0, points: 0, timestamp: 0 })
      totals[:seconds] += @run[:last] - @run[:first]
      totals[:points] += @run[:points]
      totals[:timestamp] = @run[:last]
      @run = nil
    end
  end
end

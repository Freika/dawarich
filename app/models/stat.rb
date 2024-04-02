# frozen_string_literal: true

class Stat < ApplicationRecord
  validates :year, :month, presence: true

  belongs_to :user

  def distance_by_day
    timespan.to_a.map.with_index(1) do |day, index|
      beginning_of_day = day.beginning_of_day.to_i
      end_of_day = day.end_of_day.to_i

      # We have to filter by user as well
      points = Point.where(timestamp: beginning_of_day..end_of_day)

      data = { day: index, distance: 0 }

      points.each_cons(2) do |point1, point2|
        distance = Geocoder::Calculations.distance_between(
          [point1.latitude, point1.longitude], [point2.latitude, point2.longitude]
        )

        data[:distance] += distance
      end

      [data[:day], data[:distance].round(2)]
    end
  end

  def self.year_distance(year)
    stats = where(year: year).order(:month)

    (1..12).to_a.map do |month|
      month_stat = stats.select { |stat| stat.month == month }.first

      month_name = Date::MONTHNAMES[month]
      distance = month_stat&.distance || 0

      [month_name, distance]
    end
  end

  def self.year_cities_and_countries(year)
    points = Point.where(timestamp: DateTime.new(year).beginning_of_year..DateTime.new(year).end_of_year)

    data = CountriesAndCities.new(points).call

    { countries: data.map { _1[:country] }.uniq.count, cities: data.sum { |country| country[:cities].count } }
  end

  def self.years
    starting_year = select(:year).min&.year || Time.current.year

    (starting_year..Time.current.year).to_a.reverse
  end

  private

  def timespan
    DateTime.new(year, month).beginning_of_month..DateTime.new(year, month).end_of_month
  end
end

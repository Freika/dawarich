# frozen_string_literal: true

class Stat < ApplicationRecord
  validates :year, :month, presence: true

  belongs_to :user

  def timespan
    DateTime.new(year, month).beginning_of_month..DateTime.new(year, month).end_of_month
  end

  def distance_by_day
    timespan.to_a.map.with_index(1) do |day, index|
      beginning_of_day = day.beginning_of_day.to_i
      end_of_day = day.end_of_day.to_i

      data = { day: index, distance: 0 }

      # We have to filter by user as well
      points = Point.where(timestamp: beginning_of_day..end_of_day)

      points.each_cons(2) do |point1, point2|
        distance = Geocoder::Calculations.distance_between(
          [point1.latitude, point1.longitude], [point2.latitude, point2.longitude]
        )

        data[:distance] += distance
      end

      [data[:day], data[:distance].round(2)]
    end
  end
end

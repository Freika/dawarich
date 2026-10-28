# frozen_string_literal: true

class Flight < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true
  validates :external_id, uniqueness: { scope: :user_id }

  scope :mappable, lambda {
    where.not(from_lat: nil).where.not(from_lon: nil).where.not(to_lat: nil).where.not(to_lon: nil)
  }
  scope :timed, lambda {
    where.not(distance_km: nil).where('arrival_time > departure_time')
  }

  def self.stat_months(timezone)
    dates = pluck(:flight_date, :departure_time, :arrival_time).flat_map do |flight_date, departure_time, arrival_time|
      [flight_date || departure_time&.in_time_zone(timezone)&.to_date, arrival_time&.in_time_zone(timezone)&.to_date]
    end
    dates.compact.map { [_1.year, _1.month] }.uniq
  end
end

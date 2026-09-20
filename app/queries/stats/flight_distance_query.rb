# frozen_string_literal: true

class Stats::FlightDistanceQuery
  LOCAL_FLIGHT_DATE = <<~SQL.squish
    COALESCE(
      flights.flight_date,
      (flights.departure_time AT TIME ZONE 'UTC' AT TIME ZONE :timezone)::date
    )
  SQL

  def initialize(user, year, month)
    @user = user
    @year = year.to_i
    @month = month.to_i
  end

  def call
    (flights_in_month.sum(:distance_km) * 1000).round
  end

  private

  attr_reader :user, :year, :month

  def flights_in_month
    user.flights.where(
      "#{LOCAL_FLIGHT_DATE} BETWEEN :first_day AND :last_day",
      timezone: user.timezone_iana,
      first_day: Date.new(year, month, 1),
      last_day: Date.new(year, month, -1)
    )
  end
end

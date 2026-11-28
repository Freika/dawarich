# frozen_string_literal: true

class Stats::FlightDistanceQuery
  LOCAL_FLIGHT_DATE = <<~SQL.squish
    COALESCE(
      (flights.departure_time AT TIME ZONE 'UTC' AT TIME ZONE :timezone)::date,
      flights.flight_date
    )
  SQL

  def initialize(user, year, month)
    @user = user
    @year = year.to_i
    @month = month.to_i
  end

  def call
    by_day.values.sum
  end

  def by_day
    flights_in_month
      .where.not(distance_km: nil)
      .group(Arel.sql(local_flight_date))
      .sum(:distance_km)
      .to_h { |date, km| [date.day, (km * 1000).round] }
  end

  private

  attr_reader :user, :year, :month

  def flights_in_month
    user.flights.where(
      "#{local_flight_date} BETWEEN :first_day AND :last_day",
      first_day: Date.new(year, month, 1),
      last_day: [Date.new(year, month, -1), Time.current.in_time_zone(user.timezone_iana).to_date].min
    )
  end

  def local_flight_date
    Flight.sanitize_sql_array([LOCAL_FLIGHT_DATE, { timezone: user.timezone_iana }])
  end
end

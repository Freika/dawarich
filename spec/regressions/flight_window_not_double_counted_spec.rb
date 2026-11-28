# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A recorded flight is not counted twice' do
  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC', 'minutes_between_routes' => 30 }) }
  let(:import) { create(:import, user: user) }
  let(:departure) { Time.utc(2026, 4, 20, 10) }
  let(:arrival) { departure + 3.hours }
  let(:flight_meters) { 1_870_000 }
  let(:stat) { user.stats.find_by!(year: 2026, month: 4) }

  let(:home) { 'POINT(13.30 52.50)' }
  let(:origin_airport) { 'POINT(13.50 52.36)' }
  let(:destination_airport) { 'POINT(-3.57 40.49)' }
  let(:hotel) { 'POINT(-3.70 40.42)' }

  def meters_between(from, to)
    Point.connection.select_value(
      Point.sanitize_sql_array(['SELECT ROUND(ST_Distance(?::geography, ?::geography))', from, to])
    ).to_i
  end

  def track_point(lonlat, time)
    create(:point, user: user, import: import, lonlat: lonlat, timestamp: time.to_i,
                   city: nil, country_name: nil)
  end

  before do
    track_point(home, departure - 1.hour)
    track_point(origin_airport, departure - 10.minutes)
    track_point(destination_airport, arrival + 10.minutes)
    track_point(hotel, arrival + 1.hour)
  end

  let(:ground_meters) { meters_between(home, origin_airport) + meters_between(destination_airport, hotel) }

  context 'when the flight has departure and arrival times' do
    before do
      create(:flight, user: user, flight_date: departure.to_date,
                      departure_time: departure, arrival_time: arrival, distance_km: 1870.0)
      Stats::CalculateMonth.new(user.id, 2026, 4).call
    end

    it 'counts the flown leg once, from the flight' do
      expect(stat.distance).to be_within(2).of(ground_meters + flight_meters)
    end
  end

  context 'when the flight belongs to another user' do
    before do
      create(:flight, user: create(:user), flight_date: departure.to_date,
                      departure_time: departure, arrival_time: arrival, distance_km: 1870.0)
      Stats::CalculateMonth.new(user.id, 2026, 4).call
    end

    it 'keeps the tracked leg' do
      expect(stat.distance).to be_within(2).of(
        ground_meters + meters_between(origin_airport, destination_airport)
      )
    end
  end

  context 'when the flight has a date but no times' do
    before do
      create(:flight, user: user, flight_date: departure.to_date,
                      departure_time: nil, arrival_time: nil, distance_km: 1870.0)
      Stats::CalculateMonth.new(user.id, 2026, 4).call
    end

    it 'keeps the tracked leg, since the flight cannot be placed in time' do
      expect(stat.distance).to be_within(2).of(
        ground_meters + meters_between(origin_airport, destination_airport) + flight_meters
      )
    end
  end
end

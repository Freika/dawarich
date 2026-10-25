# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Distance totals include recorded flights' do
  let(:user) { create(:user, settings: { 'timezone' => 'Etc/UTC' }) }
  let(:year) { 2026 }
  let(:month) { 4 }
  let(:flight_day) { 20 }
  let(:departure) { Time.utc(year, month, flight_day, 10) }
  let(:flight_meters) { 633_400 }
  let(:stat) { user.stats.find_by!(year: year, month: month) }
  let(:tracked_by_day) { stat.distance_by_day.to_h }

  before do
    create(:point, user: user, timestamp: (departure - 1.hour).to_i,
                   lonlat: 'POINT(-130.1 -50.1)', city: nil, country_name: nil)
    create(:point, user: user, timestamp: (departure - 50.minutes).to_i,
                   lonlat: 'POINT(-130.09 -50.1)', city: nil, country_name: nil)
    create(:flight, user: user, flight_date: departure.to_date,
                    departure_time: departure, arrival_time: departure + 2.hours,
                    from_lat: -50.1, from_lon: -130.09, to_lat: -50.1, to_lon: -121.2,
                    distance_km: 633.4)

    Stats::CalculateMonth.new(user.id, year, month).call
  end

  it 'adds the flight to the monthly total and to the day it was flown' do
    tracked = tracked_by_day.values.sum

    aggregate_failures do
      expect(tracked).to be_positive
      expect(stat.flight_distance).to eq(flight_meters)
      expect(stat.distance).to eq(tracked + flight_meters)
      expect(stat.daily_distance.to_h[flight_day]).to eq(tracked_by_day[flight_day] + flight_meters)
      expect(stat.daily_distance.sum { |_day, meters| meters }).to eq(stat.distance)
    end
  end

  it 'carries the flight into the yearly series, the user total and the yearly digest' do
    digest = Users::Digests::CalculateYear.new(user.id, year).call

    aggregate_failures do
      expect(Stat.year_distance(year, user).sum { |_month_name, meters| meters }).to eq(stat.distance)
      expect(digest.distance).to eq(stat.distance)
      expect(digest.monthly_distances.fetch(month.to_s).to_i).to eq(stat.distance)
      expect(stat.distance).to be > flight_meters
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip path and distance respect the anomaly filter', type: :model do
  let(:user) { create(:user) }
  let(:trip_start) { Time.zone.local(2026, 1, 1, 10, 0, 0) }
  let(:trip_end)   { Time.zone.local(2026, 1, 1, 12, 0, 0) }
  let(:trip)       { create(:trip, user: user, started_at: trip_start, ended_at: trip_end) }

  context 'with a mix of valid and anomaly points in the window' do
    before do
      create(:point, user: user, timestamp: (trip_start + 10.minutes).to_i,
                     longitude: 13.40, latitude: 52.50, country_name: 'Germany', anomaly: false)
      create(:point, user: user, timestamp: (trip_start + 20.minutes).to_i,
                     longitude: 13.41, latitude: 52.51, country_name: 'Germany', anomaly: nil)
      create(:point, user: user, timestamp: (trip_start + 30.minutes).to_i,
                     longitude: 13.42, latitude: 52.52, country_name: 'Germany', anomaly: false)

      create(:point, user: user, timestamp: (trip_start + 25.minutes).to_i,
                     longitude: 2.35, latitude: 48.85, country_name: 'France', anomaly: true)
      create(:point, user: user, timestamp: (trip_start + 35.minutes).to_i,
                     longitude: -0.13, latitude: 51.50, country_name: 'United Kingdom', anomaly: true)
    end

    describe '#points' do
      it 'excludes points flagged as anomalies' do
        expect(trip.points.pluck(:anomaly).uniq).to match_array([false, nil])
        expect(trip.points.count).to eq(3)
      end
    end

    describe '#calculate_countries' do
      it 'does not list countries that only appear in anomaly points' do
        trip.calculate_countries
        expect(trip.visited_countries).to eq(['Germany'])
      end
    end

    describe '#calculate_path' do
      it 'builds the path from the non-anomaly points, in order' do
        trip.calculate_path
        expect(trip.path).to be_present
        coordinate_pairs = trip.path.points.map { |p| [p.x.round(2), p.y.round(2)] }
        expect(coordinate_pairs).to eq([[13.40, 52.50], [13.41, 52.51], [13.42, 52.52]])
      end
    end

    describe '#calculate_distance' do
      it 'sums distance over non-anomaly points only' do
        trip.calculate_distance
        expect(trip.distance).to be < 10_000
      end
    end
  end

  context 'when every point in the window is an anomaly' do
    before do
      create(:point, user: user, timestamp: (trip_start + 10.minutes).to_i,
                     longitude: 2.35, latitude: 48.85, country_name: 'France', anomaly: true)
      create(:point, user: user, timestamp: (trip_start + 20.minutes).to_i,
                     longitude: -0.13, latitude: 51.50, country_name: 'United Kingdom', anomaly: true)
    end

    it 'returns no points and produces empty geometry' do
      expect(trip.points).to be_empty

      trip.calculate_path
      trip.calculate_distance
      trip.calculate_countries

      expect(trip.path).to be_nil
      expect(trip.distance).to eq(0)
      expect(trip.visited_countries).to eq([])
    end
  end
end

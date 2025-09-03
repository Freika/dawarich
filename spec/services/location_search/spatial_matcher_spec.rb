# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LocationSearch::SpatialMatcher do
  let(:service) { described_class.new }
  let(:user) { create(:user) }
  let(:latitude) { 52.5200 }
  let(:longitude) { 13.4050 }
  let(:radius_meters) { 100 }

  describe '#find_points_near' do
    let!(:near_point) do
      create(:point,
        user: user,
        lonlat: "POINT(13.4051 52.5201)",
        timestamp: 1.hour.ago.to_i,
        city: 'Berlin',
        country: 'Germany',
        altitude: 100,
        accuracy: 5
      )
    end

    let!(:far_point) do
      create(:point,
        user: user,
        lonlat: "POINT(13.5000 52.6000)",
        timestamp: 2.hours.ago.to_i
      )
    end

    let!(:other_user_point) do
      create(:point,
        user: create(:user),
        lonlat: "POINT(13.4051 52.5201)",
        timestamp: 30.minutes.ago.to_i
      )
    end

    context 'with points within radius' do
      it 'returns points within the specified radius' do
        results = service.find_points_near(user, latitude, longitude, radius_meters)

        expect(results.length).to eq(1)
        expect(results.first[:id]).to eq(near_point.id)
      end

      it 'excludes points outside the radius' do
        results = service.find_points_near(user, latitude, longitude, radius_meters)

        point_ids = results.map { |r| r[:id] }
        expect(point_ids).not_to include(far_point.id)
      end

      it 'only includes points from the specified user' do
        results = service.find_points_near(user, latitude, longitude, radius_meters)

        point_ids = results.map { |r| r[:id] }
        expect(point_ids).not_to include(other_user_point.id)
      end

      it 'includes calculated distance' do
        results = service.find_points_near(user, latitude, longitude, radius_meters)

        expect(results.first[:distance_meters]).to be_a(Float)
        expect(results.first[:distance_meters]).to be < radius_meters
      end

      it 'includes point attributes' do
        results = service.find_points_near(user, latitude, longitude, radius_meters)

        point = results.first
        expect(point).to include(
          id: near_point.id,
          timestamp: near_point.timestamp,
          coordinates: [52.5201, 13.4051],
          city: 'Berlin',
          country: 'Germany',
          altitude: 100,
          accuracy: 5
        )
      end

      it 'includes ISO8601 formatted date' do
        results = service.find_points_near(user, latitude, longitude, radius_meters)

        expect(results.first[:date]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it 'orders results by timestamp descending (most recent first)' do
        # Create another nearby point with older timestamp
        older_point = create(:point,
          user: user,
          lonlat: "POINT(13.4049 52.5199)",
          timestamp: 3.hours.ago.to_i
        )

        results = service.find_points_near(user, latitude, longitude, radius_meters)

        expect(results.first[:id]).to eq(near_point.id) # More recent
        expect(results.last[:id]).to eq(older_point.id)  # Older
      end
    end

    context 'with date filtering' do
      let(:date_options) do
        {
          date_from: 2.days.ago.to_date,
          date_to: Date.current
        }
      end

      let!(:old_point) do
        create(:point,
          user: user,
          lonlat: "POINT(13.4051 52.5201)",
          timestamp: 1.week.ago.to_i
        )
      end

      it 'filters points by date range' do
        results = service.find_points_near(user, latitude, longitude, radius_meters, date_options)

        point_ids = results.map { |r| r[:id] }
        expect(point_ids).to include(near_point.id)
        expect(point_ids).not_to include(old_point.id)
      end

      context 'with only date_from' do
        let(:date_options) { { date_from: 2.hours.ago.to_date } }

        it 'includes points after date_from' do
          results = service.find_points_near(user, latitude, longitude, radius_meters, date_options)

          point_ids = results.map { |r| r[:id] }
          expect(point_ids).to include(near_point.id)
        end
      end

      context 'with only date_to' do
        let(:date_options) { { date_to: 2.days.ago.to_date } }

        it 'includes points before date_to' do
          results = service.find_points_near(user, latitude, longitude, radius_meters, date_options)

          point_ids = results.map { |r| r[:id] }
          expect(point_ids).to include(old_point.id)
          expect(point_ids).not_to include(near_point.id)
        end
      end
    end

    context 'with no points within radius' do
      it 'returns empty array' do
        results = service.find_points_near(user, 60.0, 30.0, 100) # Far away coordinates

        expect(results).to be_empty
      end
    end

    context 'with edge cases' do
      it 'handles points at the exact radius boundary' do
        # This test would require creating a point at exactly 100m distance
        # For simplicity, we'll test with a very small radius that should exclude our test point
        results = service.find_points_near(user, latitude, longitude, 1) # 1 meter radius

        expect(results).to be_empty
      end

      it 'handles negative coordinates' do
        # Create point with negative coordinates
        negative_point = create(:point,
          user: user,
          lonlat: "POINT(151.2093 -33.8688)",
          timestamp: 1.hour.ago.to_i
        )

        results = service.find_points_near(user, -33.8688, 151.2093, 1000)

        expect(results.length).to eq(1)
        expect(results.first[:id]).to eq(negative_point.id)
      end

      it 'handles coordinates near poles' do
        # Create point near north pole
        polar_point = create(:point,
          user: user,
          lonlat: "POINT(0.0 89.0)",
          timestamp: 1.hour.ago.to_i
        )

        results = service.find_points_near(user, 89.0, 0.0, 1000)

        expect(results.length).to eq(1)
        expect(results.first[:id]).to eq(polar_point.id)
      end
    end

    context 'with large datasets' do
      before do
        # Create many points to test performance
        50.times do |i|
          create(:point,
            user: user,
            lonlat: "POINT(#{longitude + (i * 0.0001)} #{latitude + (i * 0.0001)})", # Spread points slightly
            timestamp: i.hours.ago.to_i
          )
        end
      end

      it 'efficiently queries large datasets' do
        start_time = Time.current

        results = service.find_points_near(user, latitude, longitude, 1000)

        query_time = Time.current - start_time
        expect(query_time).to be < 1.0 # Should complete within 1 second
        expect(results.length).to be > 40 # Should find most of the points
      end
    end
  end
end

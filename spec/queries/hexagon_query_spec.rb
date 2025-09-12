# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HexagonQuery, type: :query do
  let(:user) { create(:user) }
  let(:min_lon) { -74.1 }
  let(:min_lat) { 40.6 }
  let(:max_lon) { -73.9 }
  let(:max_lat) { 40.8 }
  let(:hex_size) { 500 }

  describe '#initialize' do
    it 'sets required parameters' do
      query = described_class.new(
        min_lon: min_lon,
        min_lat: min_lat,
        max_lon: max_lon,
        max_lat: max_lat,
        hex_size: hex_size
      )

      expect(query.min_lon).to eq(min_lon)
      expect(query.min_lat).to eq(min_lat)
      expect(query.max_lon).to eq(max_lon)
      expect(query.max_lat).to eq(max_lat)
      expect(query.hex_size).to eq(hex_size)
    end

    it 'sets optional parameters' do
      start_date = '2024-06-01T00:00:00Z'
      end_date = '2024-06-30T23:59:59Z'

      query = described_class.new(
        min_lon: min_lon,
        min_lat: min_lat,
        max_lon: max_lon,
        max_lat: max_lat,
        hex_size: hex_size,
        user_id: user.id,
        start_date: start_date,
        end_date: end_date
      )

      expect(query.user_id).to eq(user.id)
      expect(query.start_date).to eq(start_date)
      expect(query.end_date).to eq(end_date)
    end
  end

  describe '#call' do
    let(:query) do
      described_class.new(
        min_lon: min_lon,
        min_lat: min_lat,
        max_lon: max_lon,
        max_lat: max_lat,
        hex_size: hex_size,
        user_id: user.id
      )
    end

    context 'with no points' do
      it 'executes without error and returns empty result' do
        result = query.call
        expect(result.to_a).to be_empty
      end
    end

    context 'with points in bounding box' do
      before do
        # Create test points within the bounding box
        create(:point, 
               user:, 
               latitude: 40.7, 
               longitude: -74.0,
               timestamp: Time.new(2024, 6, 15, 12, 0).to_i)
        create(:point, 
               user:, 
               latitude: 40.75, 
               longitude: -73.95,
               timestamp: Time.new(2024, 6, 16, 14, 0).to_i)
      end

      it 'returns hexagon results with expected structure' do
        result = query.call
        result_array = result.to_a

        expect(result_array).not_to be_empty
        
        first_hex = result_array.first
        expect(first_hex).to have_key('geojson')
        expect(first_hex).to have_key('hex_i')
        expect(first_hex).to have_key('hex_j')
        expect(first_hex).to have_key('point_count')
        expect(first_hex).to have_key('earliest_point')
        expect(first_hex).to have_key('latest_point')
        expect(first_hex).to have_key('id')

        # Verify geojson can be parsed
        geojson = JSON.parse(first_hex['geojson'])
        expect(geojson).to have_key('type')
        expect(geojson).to have_key('coordinates')
      end

      it 'filters by user_id correctly' do
        other_user = create(:user)
        # Create points for a different user (should be excluded)
        create(:point, 
               user: other_user, 
               latitude: 40.72, 
               longitude: -73.98,
               timestamp: Time.new(2024, 6, 17, 16, 0).to_i)

        result = query.call
        result_array = result.to_a

        # Should only include hexagons with the specified user's points
        total_points = result_array.sum { |row| row['point_count'].to_i }
        expect(total_points).to eq(2) # Only the 2 points from our user
      end
    end

    context 'with date filtering' do
      let(:query_with_dates) do
        described_class.new(
          min_lon: min_lon,
          min_lat: min_lat,
          max_lon: max_lon,
          max_lat: max_lat,
          hex_size: hex_size,
          user_id: user.id,
          start_date: '2024-06-15T00:00:00Z',
          end_date: '2024-06-16T23:59:59Z'
        )
      end

      before do
        # Create points within and outside the date range
        create(:point, 
               user:, 
               latitude: 40.7, 
               longitude: -74.0,
               timestamp: Time.new(2024, 6, 15, 12, 0).to_i) # Within range
        create(:point, 
               user:, 
               latitude: 40.71, 
               longitude: -74.01,
               timestamp: Time.new(2024, 6, 20, 12, 0).to_i) # Outside range
      end

      it 'filters points by date range' do
        result = query_with_dates.call
        result_array = result.to_a

        expect(result_array).not_to be_empty
        
        # Should only include the point within the date range
        total_points = result_array.sum { |row| row['point_count'].to_i }
        expect(total_points).to eq(1)
      end
    end

    context 'without user_id filter' do
      let(:query_no_user) do
        described_class.new(
          min_lon: min_lon,
          min_lat: min_lat,
          max_lon: max_lon,
          max_lat: max_lat,
          hex_size: hex_size
        )
      end

      before do
        user1 = create(:user)
        user2 = create(:user)
        
        create(:point, user: user1, latitude: 40.7, longitude: -74.0, timestamp: Time.current.to_i)
        create(:point, user: user2, latitude: 40.75, longitude: -73.95, timestamp: Time.current.to_i)
      end

      it 'includes points from all users' do
        result = query_no_user.call
        result_array = result.to_a

        expect(result_array).not_to be_empty
        
        # Should include points from both users
        total_points = result_array.sum { |row| row['point_count'].to_i }
        expect(total_points).to eq(2)
      end
    end
  end

  describe '#build_date_filter (private method behavior)' do
    context 'when testing date filter behavior through query execution' do
      it 'works correctly with start_date only' do
        query = described_class.new(
          min_lon: min_lon,
          min_lat: min_lat,
          max_lon: max_lon,
          max_lat: max_lat,
          hex_size: hex_size,
          user_id: user.id,
          start_date: '2024-06-15T00:00:00Z'
        )

        # Should execute without SQL syntax errors
        expect { query.call }.not_to raise_error
      end

      it 'works correctly with end_date only' do
        query = described_class.new(
          min_lon: min_lon,
          min_lat: min_lat,
          max_lon: max_lon,
          max_lat: max_lat,
          hex_size: hex_size,
          user_id: user.id,
          end_date: '2024-06-30T23:59:59Z'
        )

        # Should execute without SQL syntax errors
        expect { query.call }.not_to raise_error
      end

      it 'works correctly with both start_date and end_date' do
        query = described_class.new(
          min_lon: min_lon,
          min_lat: min_lat,
          max_lon: max_lon,
          max_lat: max_lat,
          hex_size: hex_size,
          user_id: user.id,
          start_date: '2024-06-01T00:00:00Z',
          end_date: '2024-06-30T23:59:59Z'
        )

        # Should execute without SQL syntax errors
        expect { query.call }.not_to raise_error
      end
    end
  end
end
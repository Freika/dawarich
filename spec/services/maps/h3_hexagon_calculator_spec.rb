# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::H3HexagonCalculator, type: :service do
  let(:user) { create(:user) }
  let(:start_date) { Time.zone.parse('2024-01-01') }
  let(:end_date) { Time.zone.parse('2024-01-02') }
  let(:service) { described_class.new(user.id, start_date, end_date, 5) }

  describe '#call' do
    context 'when user has no points' do
      it 'returns error response' do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('No points found for the given date range')
      end
    end

    context 'when user has points outside date range' do
      before do
        create(:point,
               user: user,
               latitude: 52.5200,
               longitude: 13.4050,
               lonlat: 'POINT(13.4050 52.5200)',
               timestamp: end_date.to_i + 1.hour) # Outside range
      end

      it 'returns error response' do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('No points found for the given date range')
      end
    end

    context 'when user has valid points' do
      before do
        # Create points in Berlin area
        create(:point,
               user: user,
               latitude: 52.5200,
               longitude: 13.4050,
               lonlat: 'POINT(13.4050 52.5200)',
               timestamp: start_date.to_i + 1.hour)

        create(:point,
               user: user,
               latitude: 52.5190,
               longitude: 13.4040,
               lonlat: 'POINT(13.4040 52.5190)',
               timestamp: start_date.to_i + 2.hours)

        # Point outside date range
        create(:point,
               user: user,
               latitude: 52.5200,
               longitude: 13.4050,
               lonlat: 'POINT(13.4050 52.5200)',
               timestamp: end_date.to_i + 1.hour)
      end

      it 'returns successful response with hexagon features' do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:data]).to have_key(:type)
        expect(result[:data][:type]).to eq('FeatureCollection')
        expect(result[:data]).to have_key(:features)
        expect(result[:data][:features]).to be_an(Array)
        expect(result[:data][:features]).not_to be_empty
      end

      it 'creates proper GeoJSON features' do
        result = service.call
        feature = result[:data][:features].first

        expect(feature).to have_key(:type)
        expect(feature[:type]).to eq('Feature')

        expect(feature).to have_key(:geometry)
        expect(feature[:geometry][:type]).to eq('Polygon')
        expect(feature[:geometry][:coordinates]).to be_an(Array)
        expect(feature[:geometry][:coordinates].first).to be_an(Array)

        expect(feature).to have_key(:properties)
        expect(feature[:properties]).to have_key(:h3_index)
        expect(feature[:properties]).to have_key(:point_count)
        expect(feature[:properties]).to have_key(:center)
      end

      it 'only includes points within date range' do
        result = service.call

        # Should only have features from the 2 points within range
        total_points = result[:data][:features].sum { |f| f[:properties][:point_count] }
        expect(total_points).to eq(2)
      end

      it 'creates closed polygon coordinates' do
        result = service.call
        feature = result[:data][:features].first
        coordinates = feature[:geometry][:coordinates].first

        # First and last coordinates should be the same (closed polygon)
        expect(coordinates.first).to eq(coordinates.last)

        # Should have 7 coordinates (6 vertices + 1 to close)
        expect(coordinates.length).to eq(7)
      end

      it 'counts points correctly per hexagon' do
        result = service.call

        # Both points are very close, should likely be in same hexagon
        if result[:data][:features].length == 1
          expect(result[:data][:features].first[:properties][:point_count]).to eq(2)
        else
          # Or they might be in adjacent hexagons
          total_points = result[:data][:features].sum { |f| f[:properties][:point_count] }
          expect(total_points).to eq(2)
        end
      end

      it 'includes H3 index as hex string' do
        result = service.call
        feature = result[:data][:features].first

        h3_index = feature[:properties][:h3_index]
        expect(h3_index).to be_a(String)
        expect(h3_index).to match(/^[0-9a-f]+$/) # Hex string
      end

      it 'includes center coordinates' do
        result = service.call
        feature = result[:data][:features].first

        center = feature[:properties][:center]
        expect(center).to be_an(Array)
        expect(center.length).to eq(2)
        expect(center[0]).to be_between(52.0, 53.0) # Lat around Berlin
        expect(center[1]).to be_between(13.0, 14.0) # Lng around Berlin
      end
    end

    context 'with different H3 resolution' do
      let(:service) { described_class.new(user.id, start_date, end_date, 7) }

      before do
        create(:point,
               user: user,
               latitude: 52.5200,
               longitude: 13.4050,
               lonlat: 'POINT(13.4050 52.5200)',
               timestamp: start_date.to_i + 1.hour)
      end

      it 'uses the specified resolution' do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:data][:features]).not_to be_empty

        # Higher resolution should create different sized hexagons
        feature = result[:data][:features].first
        expect(feature[:properties][:h3_index]).to be_present
      end
    end

    context 'when H3 operations fail' do
      before do
        create(:point,
               user: user,
               latitude: 52.5200,
               longitude: 13.4050,
               lonlat: 'POINT(13.4050 52.5200)',
               timestamp: start_date.to_i + 1.hour)

        allow(H3).to receive(:from_geo_coordinates).and_raise(StandardError, 'H3 error')
      end

      it 'returns error response' do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('H3 error')
      end
    end

    context 'with points from different users' do
      let(:other_user) { create(:user) }

      before do
        # Points for target user
        create(:point,
               user: user,
               latitude: 52.5200,
               longitude: 13.4050,
               lonlat: 'POINT(13.4050 52.5200)',
               timestamp: start_date.to_i + 1.hour)

        # Points for other user (should be ignored)
        create(:point,
               user: other_user,
               latitude: 52.5200,
               longitude: 13.4050,
               lonlat: 'POINT(13.4050 52.5200)',
               timestamp: start_date.to_i + 1.hour)
      end

      it 'only includes points from specified user' do
        result = service.call

        total_points = result[:data][:features].sum { |f| f[:properties][:point_count] }
        expect(total_points).to eq(1)
      end
    end
  end
end
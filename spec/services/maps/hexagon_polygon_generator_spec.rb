# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::HexagonPolygonGenerator do
  describe '.call' do
    subject(:generate_polygon) do
      described_class.new(
        center_lng: center_lng,
        center_lat: center_lat
      ).call
    end

    let(:center_lng) { -74.0 }
    let(:center_lat) { 40.7 }

    it 'returns a polygon geometry using H3' do
      result = generate_h3_polygon

      expect(result['type']).to eq('Polygon')
      expect(result['coordinates']).to be_an(Array)
      expect(result['coordinates'].length).to eq(1) # One ring
    end

    it 'generates a hexagon with 7 coordinate pairs (6 vertices + closing)' do
      result = generate_h3_polygon
      coordinates = result['coordinates'].first

      expect(coordinates.length).to eq(7) # 6 vertices + closing vertex
      expect(coordinates.first).to eq(coordinates.last) # Closed polygon
    end

    it 'generates unique vertices' do
      result = generate_h3_polygon
      coordinates = result['coordinates'].first

      # Remove the closing vertex for uniqueness check
      unique_vertices = coordinates[0..5]
      expect(unique_vertices.uniq.length).to eq(6) # All vertices should be unique
    end

    it 'generates vertices around the center point' do
      result = generate_h3_polygon
      coordinates = result['coordinates'].first

      # Check that vertices have some variation in coordinates
      longitudes = coordinates[0..5].map { |vertex| vertex[0] }
      latitudes = coordinates[0..5].map { |vertex| vertex[1] }

      expect(longitudes.uniq.size).to be > 1 # Should have different longitudes
      expect(latitudes.uniq.size).to be > 1 # Should have different latitudes
    end

    context 'when H3 operations fail' do
      before do
        allow(H3).to receive(:from_geo_coordinates).and_raise(StandardError, 'H3 error')
      end

      it 'raises the H3 error' do
        expect { generate_h3_polygon }.to raise_error(StandardError, 'H3 error')
      end
    end

    private

    def calculate_hexagon_size(coordinates)
      # Calculate distance between first two vertices as size approximation
      vertex1 = coordinates[0]
      vertex2 = coordinates[1]

      lng_diff = vertex2[0] - vertex1[0]
      lat_diff = vertex2[1] - vertex1[1]

      Math.sqrt(lng_diff**2 + lat_diff**2)
    end

    def calculate_distance_from_center(vertex)
      lng, lat = vertex
      Math.sqrt((lng - center_lng)**2 + (lat - center_lat)**2)
    end
  end
end

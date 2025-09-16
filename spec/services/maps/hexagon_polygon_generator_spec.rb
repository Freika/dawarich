# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::HexagonPolygonGenerator do
  describe '.call' do
    subject(:generate_polygon) do
      described_class.call(
        center_lng: center_lng,
        center_lat: center_lat,
        size_meters: size_meters
      )
    end

    let(:center_lng) { -74.0 }
    let(:center_lat) { 40.7 }
    let(:size_meters) { 1000 }

    it 'returns a polygon geometry' do
      result = generate_polygon

      expect(result['type']).to eq('Polygon')
      expect(result['coordinates']).to be_an(Array)
      expect(result['coordinates'].length).to eq(1) # One ring
    end

    it 'generates a hexagon with 7 coordinate pairs (6 vertices + closing)' do
      result = generate_polygon
      coordinates = result['coordinates'].first

      expect(coordinates.length).to eq(7) # 6 vertices + closing vertex
      expect(coordinates.first).to eq(coordinates.last) # Closed polygon
    end

    it 'generates unique vertices' do
      result = generate_polygon
      coordinates = result['coordinates'].first

      # Remove the closing vertex for uniqueness check
      unique_vertices = coordinates[0..5]
      expect(unique_vertices.uniq.length).to eq(6) # All vertices should be unique
    end

    it 'generates vertices around the center point' do
      result = generate_polygon
      coordinates = result['coordinates'].first

      # Check that all vertices are different from center
      coordinates[0..5].each do |vertex|
        lng, lat = vertex
        expect(lng).not_to eq(center_lng)
        expect(lat).not_to eq(center_lat)
      end
    end

    context 'with different size' do
      let(:size_meters) { 500 }

      it 'generates a smaller hexagon' do
        small_result = generate_polygon
        large_result = described_class.call(
          center_lng: center_lng,
          center_lat: center_lat,
          size_meters: 2000
        )

        # Small hexagon should have vertices closer to center than large hexagon
        small_distance = calculate_distance_from_center(small_result['coordinates'].first.first)
        large_distance = calculate_distance_from_center(large_result['coordinates'].first.first)

        expect(small_distance).to be < large_distance
      end
    end

    context 'with different center coordinates' do
      let(:center_lng) { 13.4 } # Berlin
      let(:center_lat) { 52.5 }

      it 'generates hexagon around the new center' do
        result = generate_polygon
        coordinates = result[:coordinates].first

        # Check that vertices are around the Berlin coordinates
        avg_lng = coordinates[0..5].sum { |vertex| vertex[0] } / 6
        avg_lat = coordinates[0..5].sum { |vertex| vertex[1] } / 6

        expect(avg_lng).to be_within(0.01).of(center_lng)
        expect(avg_lat).to be_within(0.01).of(center_lat)
      end
    end

    private

    def calculate_distance_from_center(vertex)
      lng, lat = vertex
      Math.sqrt((lng - center_lng)**2 + (lat - center_lat)**2)
    end
  end
end
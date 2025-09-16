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

      # Check that not all vertices are the same as center (vertices should be distributed)
      vertices_equal_to_center = coordinates[0..5].count do |vertex|
        lng, lat = vertex
        lng == center_lng && lat == center_lat
      end

      expect(vertices_equal_to_center).to eq(0) # No vertex should be exactly at center

      # Check that vertices have some variation in coordinates
      longitudes = coordinates[0..5].map { |vertex| vertex[0] }
      latitudes = coordinates[0..5].map { |vertex| vertex[1] }

      expect(longitudes.uniq.size).to be > 1 # Should have different longitudes
      expect(latitudes.uniq.size).to be > 1 # Should have different latitudes
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
        coordinates = result['coordinates'].first

        # Check that vertices are around the Berlin coordinates
        avg_lng = coordinates[0..5].sum { |vertex| vertex[0] } / 6
        avg_lat = coordinates[0..5].sum { |vertex| vertex[1] } / 6

        expect(avg_lng).to be_within(0.01).of(center_lng)
        expect(avg_lat).to be_within(0.01).of(center_lat)
      end
    end

    context 'with H3 enabled' do
      subject(:generate_h3_polygon) do
        described_class.call(
          center_lng: center_lng,
          center_lat: center_lat,
          size_meters: size_meters,
          use_h3: true,
          h3_resolution: 5
        )
      end

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

      context 'with different H3 resolution' do
        it 'generates different sized hexagons' do
          low_res_result = described_class.call(
            center_lng: center_lng,
            center_lat: center_lat,
            use_h3: true,
            h3_resolution: 3
          )

          high_res_result = described_class.call(
            center_lng: center_lng,
            center_lat: center_lat,
            use_h3: true,
            h3_resolution: 7
          )

          # Different resolutions should produce different hexagon sizes
          low_res_coords = low_res_result['coordinates'].first
          high_res_coords = high_res_result['coordinates'].first

          # Calculate approximate size by measuring distance between vertices
          low_res_size = calculate_hexagon_size(low_res_coords)
          high_res_size = calculate_hexagon_size(high_res_coords)

          expect(low_res_size).to be > high_res_size
        end
      end

      context 'when H3 operations fail' do
        before do
          allow(H3).to receive(:from_geo_coordinates).and_raise(StandardError, 'H3 error')
        end

        it 'raises the H3 error' do
          expect { generate_h3_polygon }.to raise_error(StandardError, 'H3 error')
        end
      end

      it 'produces different results than mathematical hexagon' do
        h3_result = generate_h3_polygon
        math_result = described_class.call(
          center_lng: center_lng,
          center_lat: center_lat,
          size_meters: size_meters,
          use_h3: false
        )

        # H3 and mathematical hexagons should generally be different
        # (unless we're very unlucky with alignment)
        expect(h3_result['coordinates']).not_to eq(math_result['coordinates'])
      end
    end

    context 'with use_h3 parameter variations' do
      it 'defaults to mathematical hexagon when use_h3 is false' do
        result_explicit_false = described_class.call(
          center_lng: center_lng,
          center_lat: center_lat,
          use_h3: false
        )

        result_default = described_class.call(
          center_lng: center_lng,
          center_lat: center_lat
        )

        expect(result_explicit_false).to eq(result_default)
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
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maps::HexagonPolygonGenerator do
  describe '.call' do
    subject(:generate_polygon) do
      described_class.new(h3_index: h3_index).call
    end

    # Valid H3 index for NYC area (resolution 6)
    let(:h3_index) { '8a1fb46622dffff' }

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

    it 'generates vertices in proper [lng, lat] format' do
      result = generate_polygon
      coordinates = result['coordinates'].first

      coordinates.each do |vertex|
        lng, lat = vertex
        expect(lng).to be_a(Float)
        expect(lat).to be_a(Float)
        expect(lng).to be_between(-180, 180)
        expect(lat).to be_between(-90, 90)
      end
    end

    context 'with hex string index' do
      let(:h3_index) { '8a1fb46622dffff' }

      it 'handles hex string format' do
        result = generate_polygon
        expect(result['type']).to eq('Polygon')
        expect(result['coordinates'].first.length).to eq(7)
      end
    end

    context 'with integer index' do
      let(:h3_index) { 0x8a1fb46622dffff }

      it 'handles integer format' do
        result = generate_polygon
        expect(result['type']).to eq('Polygon')
        expect(result['coordinates'].first.length).to eq(7)
      end
    end

    context 'when H3 operations fail' do
      before do
        allow(H3).to receive(:to_boundary).and_raise(StandardError, 'H3 error')
      end

      it 'raises the H3 error' do
        expect { generate_polygon }.to raise_error(StandardError, 'H3 error')
      end
    end

    context 'with invalid H3 index' do
      let(:h3_index) { nil }

      it 'raises an error for invalid index' do
        expect { generate_polygon }.to raise_error(TypeError)
      end
    end
  end
end

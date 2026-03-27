# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AltitudeExtractor do
  describe '.from_raw_data' do
    context 'with OwnTracks data' do
      it 'extracts altitude from alt key' do
        raw_data = { 'alt' => 36, 'lat' => 52.225, 'lon' => 13.332 }
        expect(described_class.from_raw_data(raw_data)).to eq(36.0)
      end

      it 'extracts fractional altitude' do
        raw_data = { 'alt' => 36.7, 'lat' => 52.225, 'lon' => 13.332 }
        expect(described_class.from_raw_data(raw_data)).to eq(36.7)
      end
    end

    context 'with Overland/GeoJSON data' do
      it 'extracts altitude from properties' do
        raw_data = {
          'type' => 'Feature',
          'geometry' => { 'type' => 'Point', 'coordinates' => [-122.03, 37.33] },
          'properties' => { 'altitude' => 42.5 }
        }
        expect(described_class.from_raw_data(raw_data)).to eq(42.5)
      end

      it 'falls back to geometry coordinates[2]' do
        raw_data = {
          'type' => 'Feature',
          'geometry' => { 'type' => 'Point', 'coordinates' => [-122.03, 37.33, 17.634] },
          'properties' => {}
        }
        expect(described_class.from_raw_data(raw_data)).to eq(17.634)
      end

      it 'prefers properties altitude over coordinates' do
        raw_data = {
          'type' => 'Feature',
          'geometry' => { 'type' => 'Point', 'coordinates' => [-122.03, 37.33, 10.0] },
          'properties' => { 'altitude' => 42.5 }
        }
        expect(described_class.from_raw_data(raw_data)).to eq(42.5)
      end
    end

    context 'with Google Records data' do
      it 'extracts altitude from altitude key' do
        raw_data = { 'latitudeE7' => 533_690_550, 'longitudeE7' => 836_950_010, 'altitude' => 150.3 }
        expect(described_class.from_raw_data(raw_data)).to eq(150.3)
      end
    end

    context 'with Google Phone Takeout data' do
      it 'extracts altitude from altitudeMeters' do
        raw_data = { 'altitudeMeters' => 90.7, 'accuracyMeters' => 13 }
        expect(described_class.from_raw_data(raw_data)).to eq(90.7)
      end
    end

    context 'with GPX data (XML as hash)' do
      it 'extracts altitude from ele key' do
        raw_data = { 'lat' => '47.123', 'lon' => '11.456', 'ele' => '719.2', 'time' => '2024-01-01T12:00:00Z' }
        expect(described_class.from_raw_data(raw_data)).to eq(719.2)
      end

      it 'handles ele as numeric' do
        raw_data = { 'lat' => '47.123', 'lon' => '11.456', 'ele' => 719.2 }
        expect(described_class.from_raw_data(raw_data)).to eq(719.2)
      end
    end

    context 'with nil or empty data' do
      it 'returns nil for nil input' do
        expect(described_class.from_raw_data(nil)).to be_nil
      end

      it 'returns nil for empty hash' do
        expect(described_class.from_raw_data({})).to be_nil
      end

      it 'returns nil for non-hash input' do
        expect(described_class.from_raw_data('string')).to be_nil
      end
    end

    context 'with no altitude data present' do
      it 'returns nil when raw_data has no altitude keys' do
        raw_data = { 'latitudeE7' => 533_690_550, 'longitudeE7' => 836_950_010 }
        expect(described_class.from_raw_data(raw_data)).to be_nil
      end
    end

    context 'with zero altitude' do
      it 'returns 0.0 for explicit zero' do
        raw_data = { 'alt' => 0 }
        expect(described_class.from_raw_data(raw_data)).to eq(0.0)
      end
    end

    context 'with negative altitude (below sea level)' do
      it 'returns negative value' do
        raw_data = { 'alt' => -28.5 }
        expect(described_class.from_raw_data(raw_data)).to eq(-28.5)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::GpxSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(points).call }

    let(:points) { create_list(:point, 3) }
    let(:geojson_data) { Points::GeojsonSerializer.new(points).call }
    let(:gpx) { GPX::GeoJSON.convert_to_gpx(geojson_data:) }

    it 'returns GPX file' do
      expect(serializer).to be_a(GPX::GPXFile)
    end

    it 'includes waypoints' do
      expect(serializer.waypoints.size).to eq(3)
    end

    it 'includes waypoints with correct attributes' do
      serializer.waypoints.each_with_index do |waypoint, index|
        point = points[index]
        expect(waypoint.lat).to eq(point.latitude)
        expect(waypoint.lon).to eq(point.longitude)
        expect(waypoint.time).to eq(point.recorded_at.strftime('%FT%R:%SZ'))
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::GpxSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(points).call }

    let(:points) { create_list(:point, 3) }
    let(:geojson_data) { Points::GeojsonSerializer.new(points).call }
    let(:gpx) { GPX::GeoJSON.convert_to_gpx(geojson_data:) }

    it 'returns JSON' do
      expect(serializer).to be_a(GPX::GPXFile)
    end
  end
end

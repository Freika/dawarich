# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::GeojsonSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(points).call }

    let(:points) { create_list(:point, 3) }
    let(:expected_json) do
      {
        type: 'FeatureCollection',
        features: points.map do |point|
          {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: [point.longitude, point.latitude]
            },
            properties: PointSerializer.new(point).call
          }
        end
      }
    end

    it 'returns JSON' do
      expect(serializer).to eq(expected_json.to_json)
    end
  end
end

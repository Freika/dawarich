# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::GeojsonSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(points).call }

    let(:points) do
      (1..3).map do |i|
        create(:point, timestamp: 1.day.ago + i.minutes)
      end
    end

    let(:expected_json) do
      {
        type: 'FeatureCollection',
        features: points.map do |point|
          {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: [point.lon, point.lat]
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

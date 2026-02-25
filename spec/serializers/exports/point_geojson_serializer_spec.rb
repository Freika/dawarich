# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exports::PointGeojsonSerializer do
  describe '#call' do
    let(:user) { create(:user) }
    let(:start_time) { DateTime.new(2021, 1, 1).to_i }
    let!(:points) do
      5.times.map do |i|
        create(:point, :with_known_location, user: user, timestamp: start_time + i)
      end
    end
    let(:scope) { user.points.where(timestamp: start_time..(start_time + 10)) }

    subject(:serializer) { described_class.new(scope) }

    it 'returns a Tempfile' do
      result = serializer.call
      expect(result).to be_a(Tempfile)
      result.close!
    end

    it 'produces valid GeoJSON FeatureCollection' do
      result = serializer.call
      json = JSON.parse(result.read)
      result.close!

      expect(json['type']).to eq('FeatureCollection')
      expect(json['features'].size).to eq(5)
    end

    it 'serializes each point as a Feature with correct coordinates' do
      result = serializer.call
      json = JSON.parse(result.read)
      result.close!

      feature = json['features'].first
      expect(feature['type']).to eq('Feature')
      expect(feature['geometry']['type']).to eq('Point')
      expect(feature['geometry']['coordinates']).to be_an(Array)
      expect(feature['geometry']['coordinates'].size).to eq(2)
    end

    it 'includes point properties via PointSerializer' do
      result = serializer.call
      json = JSON.parse(result.read)
      result.close!

      properties = json['features'].first['properties']
      expect(properties).to have_key('latitude')
      expect(properties).to have_key('longitude')
      expect(properties).to have_key('timestamp')
    end

    it 'produces empty features array when no points exist' do
      scope = user.points.where(timestamp: 0..1)
      result = described_class.new(scope).call
      json = JSON.parse(result.read)
      result.close!

      expect(json['features']).to eq([])
    end
  end
end

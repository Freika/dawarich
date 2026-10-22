# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrackSegments::GeometryRecalculator do
  describe '.distance_between' do
    it 'uses the same distance in meters as other geocoder-backed track calculations' do
      snapshot_point = Data.define(:lat, :lon)
      first = snapshot_point.new(lat: 52.5, lon: 13.4)
      second = snapshot_point.new(lat: 52.6, lon: 13.5)

      distance = described_class.distance_between(first, second)
      reference = Geocoder::Calculations.distance_between(
        [first.lat, first.lon], [second.lat, second.lon], units: :km
      ) * 1000

      expect(distance).to eq(reference)
    end
  end
end

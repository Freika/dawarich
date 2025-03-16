# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BuildPath do
  describe '#call' do
    let(:coordinates) do
      [
        RGeo::Geographic.spherical_factory.point(-122.654321, 45.123456),
        RGeo::Geographic.spherical_factory.point(-122.765432, 45.234567),
        RGeo::Geographic.spherical_factory.point(-122.876543, 45.345678)
      ]
    end

    let(:service) { described_class.new(coordinates) }
    let(:result) { service.call }

    it 'returns an RGeo::Geographic::SphericalLineString' do
      expect(result).to be_a(RGeo::Geographic::SphericalLineStringImpl)
    end

    it 'creates a line string with the correct number of points' do
      expect(result.num_points).to eq(coordinates.length)
    end

    it 'correctly converts coordinates to points with rounded values' do
      points = result.points

      coordinates.each_with_index do |coordinate_pair, index|
        expect(points[index].x).to eq(coordinate_pair.lon.to_f.round(5))
        expect(points[index].y).to eq(coordinate_pair.lat.to_f.round(5))
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BuildPath do
  describe '#call' do
    let(:coordinates) do
      [
        [45.123456, -122.654321], # [lat, lng]
        [45.234567, -122.765432],
        [45.345678, -122.876543]
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

      coordinates.each_with_index do |(lat, lng), index|
        expect(points[index].x).to eq(lng.to_f.round(5))
        expect(points[index].y).to eq(lat.to_f.round(5))
      end
    end
  end
end

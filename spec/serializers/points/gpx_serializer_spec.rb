# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::GpxSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(points, 'some_name').call }

    let(:country) do
      Country.create!(
        name: 'Test Country',
        iso_a2: 'TC',
        iso_a3: 'TST',
        geom: 'MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))'
      )
    end

    let(:points) do
      # Create points with country_id set to skip the set_country callback
      # which would trigger N+1 queries for country lookups
      (1..3).map do |i|
        create(:point, timestamp: 1.day.ago + i.minutes, country_id: country.id)
      end
    end

    it 'returns GPX file' do
      expect(serializer).to be_a(GPX::GPXFile)
    end

    it 'includes waypoints' do
      expect(serializer.tracks[0].points.size).to eq(3)
    end

    it 'includes waypoints with correct attributes' do
      serializer.tracks[0].points.each_with_index do |track_point, index|
        point = points[index]

        expect(track_point.lat.to_s).to eq(point.lat.to_s)
        expect(track_point.lon.to_s).to eq(point.lon.to_s)
        expect(track_point.time).to eq(point.recorded_at)
      end
    end
  end
end

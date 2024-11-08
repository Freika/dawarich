# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::GpxSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(points, 'some_name').call }

    let(:points) { create_list(:point, 3) }

    it 'returns GPX file' do
      expect(serializer).to be_a(GPX::GPXFile)
    end

    it 'includes waypoints' do
      expect(serializer.tracks[0].points.size).to eq(3)
    end

    it 'includes waypoints with correct attributes' do
      serializer.tracks[0].points.each_with_index do |track_point, index|
        point = points[index]

        expect(track_point.lat).to eq(point.latitude)
        expect(track_point.lon).to eq(point.longitude)
        expect(track_point.time).to eq(point.recorded_at)
      end
    end
  end
end

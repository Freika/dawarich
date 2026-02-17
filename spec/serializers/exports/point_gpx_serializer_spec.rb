# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exports::PointGpxSerializer do
  describe '#call' do
    let(:user) { create(:user) }
    let(:start_time) { DateTime.new(2021, 1, 1).to_i }
    let!(:points) do
      5.times.map do |i|
        create(:point, :with_known_location, user: user, timestamp: start_time + i,
               velocity: '10.5', course: 180.0)
      end
    end
    let(:scope) { user.points.where(timestamp: start_time..(start_time + 10)) }

    subject(:serializer) { described_class.new(scope, 'test_export') }

    it 'returns a Tempfile' do
      result = serializer.call
      expect(result).to be_a(Tempfile)
      result.close!
    end

    it 'produces valid XML with GPX structure' do
      result = serializer.call
      content = result.read
      result.close!

      expect(content).to include('<?xml version="1.0"')
      expect(content).to include('<gpx xmlns="http://www.topografix.com/GPX/1/1"')
      expect(content).to include('<trk>')
      expect(content).to include('<trkseg>')
      expect(content).to include('</gpx>')
    end

    it 'includes the export name in the track' do
      result = serializer.call
      content = result.read
      result.close!

      expect(content).to include('<name>dawarich_test_export</name>')
    end

    it 'includes trackpoints with lat/lon' do
      result = serializer.call
      content = result.read
      result.close!

      expect(content.scan('<trkpt').size).to eq(5)
      expect(content).to include('lat=')
      expect(content).to include('lon=')
    end

    it 'includes elevation, speed, time, and course extensions' do
      result = serializer.call
      content = result.read
      result.close!

      expect(content).to include('<ele>')
      expect(content).to include('<speed>')
      expect(content).to include('<time>')
      expect(content).to include('<extensions>')
      expect(content).to include('<course>')
    end

    it 'omits speed when velocity is zero' do
      create(:point, :with_known_location, user: user, timestamp: start_time + 100, velocity: '0')
      scope = user.points.where(timestamp: (start_time + 100)..(start_time + 101))
      result = described_class.new(scope, 'test').call
      content = result.read
      result.close!

      expect(content).not_to include('<speed>')
    end

    it 'omits course extensions when course is nil' do
      create(:point, :with_known_location, user: user, timestamp: start_time + 200, course: nil)
      scope = user.points.where(timestamp: (start_time + 200)..(start_time + 201))
      result = described_class.new(scope, 'test').call
      content = result.read
      result.close!

      expect(content).not_to include('<extensions>')
    end
  end
end

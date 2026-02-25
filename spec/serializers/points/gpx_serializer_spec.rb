# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::GpxSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(points, 'some_name').call }

    let(:points) do
      (1..3).map do |i|
        create(:point, timestamp: 1.day.ago + i.minutes, velocity: i * 10.5, course: i * 45.2)
      end
    end

    it 'returns GPX file' do
      expect(serializer).to be_a(GPX::GPXFile)
    end

    it 'includes waypoints in XML output' do
      gpx_xml = serializer.to_s

      # Check that all 3 points are included in XML
      expect(gpx_xml.scan(/<trkpt/).size).to eq(3)

      # Check that basic point data is included
      points.each do |point|
        expect(gpx_xml).to include("lat=\"#{point.lat}\"")
        expect(gpx_xml).to include("lon=\"#{point.lon}\"")
        expect(gpx_xml).to include("<ele>#{point.altitude.to_f}</ele>")
      end
    end

    it 'includes speed and course data in the GPX XML output' do
      gpx_xml = serializer.to_s

      # Check that speed is included in XML for points with velocity
      expect(gpx_xml).to include('<speed>10.5</speed>')
      expect(gpx_xml).to include('<speed>21.0</speed>')
      expect(gpx_xml).to include('<speed>31.5</speed>')

      # Check that course is included in extensions for points with course data
      expect(gpx_xml).to include('<course>45.2</course>')
      expect(gpx_xml).to include('<course>90.4</course>')
      expect(gpx_xml).to include('<course>135.6</course>')
    end

    context 'when points have nil velocity or course' do
      let(:points) do
        [
          create(:point, timestamp: 1.day.ago, velocity: nil, course: nil),
          create(:point, timestamp: 1.day.ago + 1.minute, velocity: 15.5, course: nil),
          create(:point, timestamp: 1.day.ago + 2.minutes, velocity: nil, course: 90.0)
        ]
      end

      it 'handles nil values gracefully in XML output' do
        gpx_xml = serializer.to_s

        # Should only include speed for the point with velocity
        expect(gpx_xml).to include('<speed>15.5</speed>')
        expect(gpx_xml).not_to include('<speed>0</speed>') # Should not include zero/nil speeds

        # Should only include course for the point with course data
        expect(gpx_xml).to include('<course>90.0</course>')

        # Should have 3 track points total
        expect(gpx_xml.scan(/<trkpt/).size).to eq(3)
      end
    end
  end
end

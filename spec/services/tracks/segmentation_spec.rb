# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::Segmentation do
  let(:segmenter_class) do
    Class.new do
      include Tracks::Segmentation

      def initialize(time_threshold_minutes: 30)
        @threshold = time_threshold_minutes
      end

      private

      attr_reader :threshold

      def time_threshold_minutes
        @threshold
      end
    end
  end

  let(:segmenter) { segmenter_class.new(time_threshold_minutes: 60) }

  describe '#split_points_into_segments_geocoder' do
    let(:base_time) { Time.zone.now.to_i }

    it 'keeps large spatial jumps within the same segment when time gap is below the threshold' do
      points = [
        build(:point, timestamp: base_time, latitude: 0, longitude: 0, lonlat: 'POINT(0 0)'),
        build(:point, timestamp: base_time + 5.minutes.to_i, latitude: 80, longitude: 170, lonlat: 'POINT(170 80)')
      ]

      segments = segmenter.send(:split_points_into_segments_geocoder, points)

      expect(segments.length).to eq(1)
      expect(segments.first).to eq(points)
    end

    it 'splits segments when the time gap exceeds the threshold' do
      points = [
        build(:point, timestamp: base_time, latitude: 0, longitude: 0, lonlat: 'POINT(0 0)'),
        build(:point, timestamp: base_time + 5.minutes.to_i, latitude: 0.1, longitude: 0.1, lonlat: 'POINT(0.1 0.1)'),
        build(:point, timestamp: base_time + 2.hours.to_i, latitude: 1, longitude: 1, lonlat: 'POINT(1 1)'),
        build(:point, timestamp: base_time + 2.hours.to_i + 10.minutes.to_i, latitude: 1.1, longitude: 1.1,
lonlat: 'POINT(1.1 1.1)')
      ]

      segments = segmenter.send(:split_points_into_segments_geocoder, points)

      expect(segments.length).to eq(2)
      expect(segments.first).to eq(points.first(2))
      expect(segments.last).to eq(points.last(2))
    end

    it 'ends a journey at arrival and starts the next at departure after a long stationary stop' do
      points = (0..30).map do |index|
        step = index <= 2 ? index : [2, index - 26].max
        build(:point, timestamp: base_time + index * 5.minutes.to_i,
                      lonlat: "POINT(#{-140.0 + step * 0.002} -40.0)")
      end

      segments = segmenter.send(:split_points_into_segments_geocoder, points)

      expect(segments).to eq([points.first(3), points.last(3)])
    end

    it 'keeps a stationary stop at the time threshold within the journey' do
      points = (0..16).map do |index|
        step = index <= 2 ? index : [2, index - 12].max
        build(:point, timestamp: base_time + index * 5.minutes.to_i,
                      lonlat: "POINT(#{-140.0 + step * 0.002} -40.0)")
      end

      expect(segmenter.send(:split_points_into_segments_geocoder, points)).to eq([points])
    end

    it 'keeps a densely sampled journey whose steps are each shorter than the stationary radius' do
      points = (0..480).map do |index|
        build(:point, timestamp: base_time + index * 10, lonlat: "POINT(#{-140.0 + index * 0.00075} -40.0)")
      end

      expect(segmenter.send(:split_points_into_segments_geocoder, points)).to eq([points])
    end

    it 'splits at a long jittery stop reached by a densely sampled approach' do
      approach = (0..59).map do |index|
        build(:point, timestamp: base_time + index * 10, lonlat: "POINT(#{-140.0 + index * 0.00075} -40.0)")
      end
      stop = (1..120).map do |minute|
        build(:point, timestamp: approach.last.timestamp + minute * 60,
                      lonlat: "POINT(#{approach.last.lon} #{-40.0 + (minute.even? ? 0.0002 : -0.0002)})")
      end
      departure = (1..30).map do |index|
        build(:point, timestamp: stop.last.timestamp + index * 10,
                      lonlat: "POINT(#{approach.last.lon + index * 0.0015} -40.0)")
      end

      segments = segmenter.send(:split_points_into_segments_geocoder, approach + stop + departure)

      expect(segments.size).to eq(2)
      expect(segments.first).to eq(approach.first(segments.first.size))
      expect(segments.first.size).to be >= approach.size - 1
      expect(segments.last).to eq([stop.last] + departure)
    end

    it 'does not treat a recording gap at one place as a stop' do
      before_gap = build(:point, timestamp: base_time, lonlat: 'POINT(-140.0 -40.0)')
      morning = (0..14).map do |index|
        build(:point, timestamp: base_time + 8.hours.to_i + index * 5.minutes.to_i,
                      lonlat: "POINT(#{-140.0 + [index - 12, 0].max * 0.002} -40.0)")
      end

      expect(segmenter.send(:split_points_into_segments_geocoder, [before_gap] + morning)).to eq([morning])
    end

    it 'keeps a slow crawl that leaves the stationary radius within the journey' do
      points = (0..18).map do |index|
        build(:point, timestamp: base_time + index * 5.minutes.to_i, lonlat: "POINT(#{-140.0 + index * 0.0006} -40.0)")
      end

      expect(segmenter.send(:split_points_into_segments_geocoder, points)).to eq([points])
    end
  end
end

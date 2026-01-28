# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::Detector do
  let(:user) { create(:user) }
  let(:track) { create(:track, user: user) }

  describe '#call' do
    context 'when track has fewer than 2 points' do
      let(:points) { [build(:point, user: user, timestamp: 1000)] }

      it 'returns default unknown segment' do
        detector = described_class.new(track, points)
        segments = detector.call

        expect(segments.length).to eq(1)
        expect(segments[0][:mode]).to eq(:unknown)
        expect(segments[0][:source]).to eq('default')
      end
    end

    context 'when track duration is very short' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, velocity: '10'),
          build(:point, user: user, timestamp: 1010, velocity: '10') # 10 seconds
        ]
      end

      it 'returns default unknown segment' do
        detector = described_class.new(track, points)
        segments = detector.call

        expect(segments.length).to eq(1)
        expect(segments[0][:mode]).to eq(:unknown)
      end
    end

    context 'when points have source activity data' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                }),
          build(:point, user: user, timestamp: 1100, raw_data: {
                  'properties' => { 'motion' => ['driving'] }
                })
        ]
      end

      it 'uses source data extractor' do
        detector = described_class.new(track, points)
        segments = detector.call

        expect(segments.length).to eq(1)
        expect(segments[0][:mode]).to eq(:driving)
        expect(segments[0][:source]).to eq('overland')
      end
    end

    context 'when points have no source activity data' do
      let(:points) do
        [
          build(:point, user: user, timestamp: 1000, velocity: '1.5',
            lonlat: 'POINT(13.404954 52.520008)'),
          build(:point, user: user, timestamp: 1060, velocity: '1.5',
            lonlat: 'POINT(13.405054 52.520108)'),
          build(:point, user: user, timestamp: 1120, velocity: '1.5',
            lonlat: 'POINT(13.405154 52.520208)')
        ]
      end

      it 'falls back to movement analyzer' do
        detector = described_class.new(track, points)
        segments = detector.call

        expect(segments).not_to be_empty
        expect(segments[0][:source]).to eq('inferred')
      end
    end

    context 'integration: multi-mode track' do
      let(:points) do
        # Simulate walking, then driving, then walking
        walking_points = (0..5).map do |i|
          build(:point, user: user,
            timestamp: 1000 + (i * 60),
            velocity: '1.5', # ~5.4 km/h
            lonlat: "POINT(13.#{404_954 + i} 52.#{520_008 + i})",
            raw_data: { 'properties' => { 'motion' => ['walking'] } })
        end

        driving_points = (6..15).map do |i|
          build(:point, user: user,
            timestamp: 1000 + (i * 60),
            velocity: '15', # ~54 km/h
            lonlat: "POINT(13.#{404_954 + i * 10} 52.#{520_008 + i * 10})",
            raw_data: { 'properties' => { 'motion' => ['driving'] } })
        end

        walking_points + driving_points
      end

      it 'detects multiple segments' do
        detector = described_class.new(track, points)
        segments = detector.call

        modes = segments.map { |s| s[:mode] }
        expect(modes).to include(:walking)
        expect(modes).to include(:driving)
      end
    end
  end
end

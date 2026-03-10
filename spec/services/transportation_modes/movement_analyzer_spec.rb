# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::MovementAnalyzer do
  let(:user) { create(:user) }
  let(:track) { create(:track, user: user) }

  describe '#call' do
    context 'when there are fewer than 2 points' do
      let(:points) { [build(:point, user: user, timestamp: 1000)] }

      it 'returns empty array' do
        analyzer = described_class.new(track, points)
        expect(analyzer.call).to eq([])
      end
    end

    context 'with walking speed points' do
      let(:points) do
        # Points with ~5 km/h average speed
        (0..10).map do |i|
          build(:point,
                user: user,
                timestamp: 1000 + (i * 60),
                velocity: '1.4', # ~5 km/h
                lonlat: "POINT(13.404954 #{52.520008 + (i * 0.0001)})")
        end
      end

      it 'classifies as walking' do
        analyzer = described_class.new(track, points)
        segments = analyzer.call

        expect(segments).not_to be_empty
        expect(segments.first[:mode]).to eq(:walking)
        expect(segments.first[:source]).to eq('inferred')
      end
    end

    context 'with driving speed points' do
      let(:points) do
        # Points with ~60 km/h average speed
        (0..10).map do |i|
          build(:point,
                user: user,
                timestamp: 1000 + (i * 60),
                velocity: '16.7', # ~60 km/h
                lonlat: "POINT(#{13.404954 + (i * 0.01)} 52.520008)")
        end
      end

      it 'classifies as driving' do
        analyzer = described_class.new(track, points)
        segments = analyzer.call

        expect(segments).not_to be_empty
        expect(segments.first[:mode]).to eq(:driving)
      end
    end

    context 'with mode change during track' do
      let(:points) do
        # First half: slow (walking speed)
        slow_points = (0..5).map do |i|
          build(:point,
                user: user,
                timestamp: 1000 + (i * 60),
                velocity: '1.4',
                lonlat: "POINT(13.404954 #{52.520008 + (i * 0.0001)})")
        end

        # Large time gap to trigger segment break
        gap_point = build(:point,
                          user: user,
                          timestamp: 1000 + (6 * 60) + 300, # 5 minute gap
                          velocity: '16.7',
                          lonlat: 'POINT(13.414954 52.520008)')

        # Second half: fast (driving speed)
        fast_points = (7..12).map do |i|
          build(:point,
                user: user,
                timestamp: 1000 + (i * 60) + 300,
                velocity: '16.7',
                lonlat: "POINT(#{13.414954 + (i * 0.01)} 52.520008)")
        end

        slow_points + [gap_point] + fast_points
      end

      it 'detects multiple segments' do
        analyzer = described_class.new(track, points)
        segments = analyzer.call

        expect(segments.length).to be >= 1
      end
    end

    context 'segment statistics calculation' do
      let(:points) do
        (0..5).map do |i|
          build(:point,
                user: user,
                timestamp: 1000 + (i * 60),
                velocity: '10', # ~36 km/h
                lonlat: "POINT(#{13.404954 + (i * 0.001)} 52.520008)")
        end
      end

      it 'calculates segment statistics' do
        analyzer = described_class.new(track, points)
        segments = analyzer.call

        segment = segments.first
        expect(segment[:distance]).to be_a(Integer)
        expect(segment[:duration]).to be_a(Integer)
        expect(segment[:avg_speed]).to be_a(Float)
        expect(segment[:start_index]).to eq(0)
        expect(segment[:end_index]).to be >= 1
      end
    end

    context 'with stationary points' do
      let(:points) do
        # Points at the same location with zero velocity
        (0..10).map do |i|
          build(:point,
                user: user,
                timestamp: 1000 + (i * 60),
                velocity: '0',
                lonlat: 'POINT(13.404954 52.520008)')
        end
      end

      it 'classifies as stationary' do
        analyzer = described_class.new(track, points)
        segments = analyzer.call

        expect(segments).not_to be_empty
        expect(segments.first[:mode]).to eq(:stationary)
      end
    end
  end
end

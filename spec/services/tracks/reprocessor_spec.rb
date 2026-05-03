# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::Reprocessor do
  describe 'preservation of manually-corrected segments (Option β)' do
    let(:user) { create(:user) }
    let(:track) { create(:track, user: user) }

    before do
      30.times do |i|
        create(
          :point,
          track: track,
          user: user,
          lonlat: "POINT(#{i * 0.001} 0)",
          timestamp: (Time.current + i.minutes).to_i
        )
      end
    end

    it 'deletes only auto-classified segments and preserves manually-corrected ones' do
      preserved = create(
        :track_segment,
        track: track,
        transportation_mode: :cycling,
        start_index: 5,
        end_index: 10,
        corrected_at: 1.day.ago
      )
      auto = create(
        :track_segment,
        track: track,
        transportation_mode: :driving,
        start_index: 15,
        end_index: 25,
        corrected_at: nil
      )

      allow_any_instance_of(TransportationModes::Detector).to receive(:call).and_return([])

      described_class.new(track: track).reprocess_single

      expect(TrackSegment.exists?(preserved.id)).to be true
      expect(TrackSegment.exists?(auto.id)).to be false
    end

    it 'drops newly-detected segments whose index range overlaps a preserved correction' do
      create(
        :track_segment,
        track: track,
        transportation_mode: :cycling,
        start_index: 5,
        end_index: 15,
        corrected_at: 1.day.ago
      )

      detector_segments = [
        { mode: :driving, start_index: 0, end_index: 4, distance: 100, duration: 60,
          avg_speed: 30.0, max_speed: 40.0, avg_acceleration: 0.5, confidence: :medium, source: 'inferred' },
        { mode: :driving, start_index: 10, end_index: 20, distance: 200, duration: 120,
          avg_speed: 30.0, max_speed: 40.0, avg_acceleration: 0.5, confidence: :medium, source: 'inferred' },
        { mode: :walking, start_index: 21, end_index: 29, distance: 50, duration: 300,
          avg_speed: 5.0, max_speed: 7.0, avg_acceleration: 0.1, confidence: :medium, source: 'inferred' }
      ]

      allow_any_instance_of(TransportationModes::Detector).to receive(:call).and_return(detector_segments)

      described_class.new(track: track).reprocess_single

      ranges = track.track_segments.reload.pluck(:start_index, :end_index).sort
      expect(ranges).to eq([[0, 4], [5, 15], [21, 29]])
    end

    it 'recomputes dominant_mode across the union of preserved + new segments' do
      create(
        :track_segment,
        track: track,
        transportation_mode: :cycling,
        start_index: 0,
        end_index: 5,
        duration: 1000,
        corrected_at: 1.day.ago
      )

      detector_segments = [
        { mode: :walking, start_index: 6, end_index: 15, distance: 50, duration: 300,
          avg_speed: 5.0, max_speed: 7.0, avg_acceleration: 0.1, confidence: :medium, source: 'inferred' },
        { mode: :driving, start_index: 16, end_index: 29, distance: 1000, duration: 500,
          avg_speed: 30.0, max_speed: 40.0, avg_acceleration: 0.5, confidence: :medium, source: 'inferred' }
      ]

      allow_any_instance_of(TransportationModes::Detector).to receive(:call).and_return(detector_segments)

      described_class.new(track: track).reprocess_single

      expect(track.reload.dominant_mode).to eq('cycling')
    end

    it 'passes enabled_transportation_modes from the user to the Detector' do
      user.update!(settings: (user.settings || {}).merge('enabled_transportation_modes' => %w[walking cycling]))

      captured = {}
      allow(TransportationModes::Detector).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        captured[:enabled_modes] = kwargs[:enabled_modes]
        instance = original.call(*args, **kwargs)
        allow(instance).to receive(:call).and_return([])
        instance
      end

      described_class.new(track: track).reprocess_single

      expect(captured[:enabled_modes]).to eq(%w[walking cycling])
    end

    context 'when a preserved segment has indices that exceed the current points count' do
      it 'deletes the out-of-bounds preserved segment instead of leaving it dangling' do
        out_of_bounds = create(
          :track_segment,
          track: track,
          transportation_mode: :walking,
          start_index: 25,
          end_index: 99,
          corrected_at: 1.day.ago
        )

        in_bounds = create(
          :track_segment,
          track: track,
          transportation_mode: :cycling,
          start_index: 0,
          end_index: 5,
          corrected_at: 1.day.ago
        )

        allow_any_instance_of(TransportationModes::Detector).to receive(:call).and_return([])

        described_class.new(track: track).reprocess_single

        expect(TrackSegment.exists?(out_of_bounds.id)).to be false
        expect(TrackSegment.exists?(in_bounds.id)).to be true
      end
    end
  end
end

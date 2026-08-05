# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::Reprocessor do
  describe 'preservation of manually-corrected segments' do
    let(:user) { create(:user) }
    let(:track) { create(:track, user: user) }
    let(:base_ts) { Time.current.to_i }

    before do
      30.times do |i|
        create(
          :point,
          track: track,
          user: user,
          lonlat: "POINT(#{i * 0.001} 0)",
          timestamp: base_ts + (i * 60)
        )
      end
    end

    def time_segment(mode:, from:, to:, duration: nil, distance: 100)
      { mode: mode,
        start_at: Time.zone.at(base_ts + from), end_at: Time.zone.at(base_ts + to),
        path_wkt: nil, distance: distance, duration: duration || (to - from),
        avg_speed: 10.0, max_speed: 20.0, confidence: :medium, confidence_score: 0.7,
        source: 'inferred' }
    end

    it 'deletes only auto-classified segments and preserves manually-corrected ones' do
      preserved = create(:track_segment, :anchored, track: track,
                                                    transportation_mode: :cycling, corrected_at: 1.day.ago)
      auto = create(:track_segment, :anchored, track: track,
                                               transportation_mode: :driving, corrected_at: nil)

      allow_any_instance_of(TransportationModes::Detector).to receive(:call).and_return([])

      described_class.new(track: track).reprocess_single

      expect(TrackSegment.exists?(preserved.id)).to be true
      expect(TrackSegment.exists?(auto.id)).to be false
    end

    it 'passes preserved corrected segments and enabled modes to the Detector' do
      user.update!(settings: (user.settings || {}).merge('enabled_transportation_modes' => %w[walking cycling]))
      preserved = create(:track_segment, :anchored, track: track,
                                                    transportation_mode: :bus, corrected_at: 1.day.ago)

      captured = {}
      allow(TransportationModes::Detector).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        captured[:enabled_modes] = kwargs[:enabled_modes]
        captured[:preserved] = kwargs[:preserved]
        instance = original.call(*args, **kwargs)
        allow(instance).to receive(:call).and_return([])
        instance
      end

      described_class.new(track: track).reprocess_single

      expect(captured[:enabled_modes]).to eq(%w[walking cycling])
      expect(captured[:preserved].map(&:id)).to eq([preserved.id])
    end

    it 'inserts detector output as time-anchored segments' do
      segments = [
        time_segment(mode: :walking, from: 0, to: 600),
        time_segment(mode: :driving, from: 600, to: 1740)
      ]
      allow_any_instance_of(TransportationModes::Detector).to receive(:call).and_return(segments)

      described_class.new(track: track).reprocess_single

      stored = track.track_segments.reload.order(:start_at)
      expect(stored.map(&:transportation_mode)).to eq(%w[walking driving])
      expect(stored.first.start_at.to_i).to eq(base_ts)
    end

    it 'recomputes dominant_mode across the union of preserved + new segments' do
      create(:track_segment, :anchored, track: track, transportation_mode: :cycling,
                                        duration: 5_000, distance: 100, corrected_at: 1.day.ago)

      segments = [
        time_segment(mode: :walking, from: 0, to: 300, duration: 300),
        time_segment(mode: :driving, from: 300, to: 800, duration: 500)
      ]
      allow_any_instance_of(TransportationModes::Detector).to receive(:call).and_return(segments)

      described_class.new(track: track).reprocess_single

      expect(track.reload.dominant_mode).to eq('cycling')
    end
  end
end

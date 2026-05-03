# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::SegmentEditor do
  let(:user) { create(:user) }
  let(:track) { create(:track, user: user) }

  describe '#apply_override' do
    let(:segment) do
      create(:track_segment, track: track,
             transportation_mode: :cycling,
             avg_speed: 15, max_speed: 18, avg_acceleration: 0.1, duration: 600,
             corrected_at: nil, source: 'gps', confidence: :medium)
    end

    it 'sets transportation_mode and stamps corrected_at' do
      result = described_class.new(segment, user).apply_override('walking')
      expect(result.success?).to be true
      segment.reload
      expect(segment.transportation_mode).to eq('walking')
      expect(segment.corrected_at).to be_within(5.seconds).of(Time.current)
      expect(segment.confidence).to eq('high')
      expect(segment.source).to eq('user')
    end

    it 'rejects when mode is not in user allowlist' do
      user.settings['enabled_transportation_modes'] = %w[walking cycling]
      user.save!

      result = described_class.new(segment, user).apply_override('flying')
      expect(result.success?).to be false
      expect(result.error_code).to eq(:mode_not_enabled)
      expect(segment.reload.transportation_mode).to eq('cycling')
    end

    it 'recomputes Track#dominant_mode after override' do
      create(:track_segment, track: track,
                     transportation_mode: :driving,
                     duration: 100, corrected_at: nil)

      described_class.new(segment, user).apply_override('walking')
      expected = track.track_segments.reload.max_by { |s| s.duration || 0 }.transportation_mode
      expect(track.reload.dominant_mode).to eq(expected)
    end
  end

  describe '#reset_to_auto' do
    let(:segment) do
      create(:track_segment, track: track,
             transportation_mode: :walking,
             avg_speed: 15, max_speed: 18, avg_acceleration: 0.1, duration: 600,
             corrected_at: 1.day.ago, source: 'user', confidence: :high)
    end

    it 'clears corrected_at and re-runs ModeClassifier on stored summary metrics' do
      result = described_class.new(segment, user).reset_to_auto
      expect(result.success?).to be true
      segment.reload
      expect(segment.corrected_at).to be_nil
      expect(segment.source).to eq('gps')
    end

    it 'respects the current allowlist when re-classifying' do
      user.settings['enabled_transportation_modes'] = %w[walking running]
      user.save!

      described_class.new(segment, user).reset_to_auto
      expect(segment.reload.transportation_mode).to be_in(%w[walking running unknown])
    end
  end
end

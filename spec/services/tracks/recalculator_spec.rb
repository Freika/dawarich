# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::Recalculator do
  let(:user) { create(:user) }
  let(:track) do
    create(:track, user:, start_at: Time.zone.at(1_000), end_at: Time.zone.at(1_120),
                   original_path: 'LINESTRING(0 0, 0.01 0)')
  end

  before do
    create(:point, user:, track:, timestamp: 1_000, longitude: 0, latitude: 0)
    create(:point, user:, track:, timestamp: 1_060, longitude: 0.01, latitude: 0)
    create(:point, user:, track:, timestamp: 1_120, longitude: 0.02, latitude: 0)
  end

  it 'recalculates the track and its index-anchored segments from one point snapshot' do
    segment = create(:track_segment, track:, start_index: 0, end_index: 1)

    described_class.call(track)

    expect(track.reload.original_path.points.map(&:x)).to eq([0.0, 0.01, 0.02])
    expect(track.distance).to be_between(2_220, 2_230)
    expect(track.duration).to eq(120)
    expect(track.avg_speed).to be_between(66.0, 67.0)
    expect(segment.reload.path.points.map(&:x)).to eq([0.0, 0.01])
    expect(segment.distance).to be_between(1_110, 1_120)
    expect(segment.transportation_mode).to eq('driving')
  end

  it 'preserves manual correction metadata on time-anchored segments' do
    corrected_at = 1.day.ago
    segment = create(:track_segment, :anchored, track:, start_at: Time.zone.at(1_000),
                                                end_at: Time.zone.at(1_120),
                                                corrected_at:, transportation_mode: :walking)
    persisted_correction = segment.reload.corrected_at

    described_class.call(track)

    expect(segment.reload).to have_attributes(
      transportation_mode: 'walking',
      corrected_at: persisted_correction
    )
    expect(segment.path.points.size).to eq(3)
  end
end

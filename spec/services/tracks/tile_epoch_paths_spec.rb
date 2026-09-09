# frozen_string_literal: true

require 'rails_helper'

# Every track write path must invalidate the tracks tile epoch — a missed bump
# serves deleted/changed tracks under a stable ETag indefinitely.
RSpec.describe 'Tracks::TileEpoch write paths' do
  let(:user) { create(:user) }

  def component(year)
    Tracks::TileEpoch.etag_component(
      user.id, Time.utc(year, 1, 1).to_i, Time.utc(year, 12, 31).to_i
    )
  end

  def build_track(attrs = {})
    create(:track, user:,
                   start_at: Time.utc(2024, 6, 1, 10), end_at: Time.utc(2024, 6, 1, 12),
                   **attrs)
  end

  it 'bumps on create' do
    before = component(2024)
    build_track
    expect(component(2024)).not_to eq(before)
  end

  it 'bumps on destroy' do
    track = build_track
    before = component(2024)
    track.destroy!
    expect(component(2024)).not_to eq(before)
  end

  it 'bumps on update, including an attribute-only change' do
    track = build_track
    before = component(2024)
    track.update!(dominant_mode: :driving)
    expect(component(2024)).not_to eq(before)
  end

  it 'bumps BOTH years when a track with points moves across a year boundary' do
    track = build_track
    2.times do |i|
      create(:point, user:, timestamp: Time.utc(2024, 6, 1, 10 + i).to_i, track:)
    end

    before_2024 = component(2024)
    before_2025 = component(2025)

    track.update!(start_at: Time.utc(2025, 2, 1, 10), end_at: Time.utc(2025, 2, 1, 12))

    expect(component(2024)).not_to eq(before_2024)
    expect(component(2025)).not_to eq(before_2025)
  end

  it 'bumps from Track.delete_orphaned even though delete_all skips callbacks' do
    track = build_track
    before = component(2024)

    expect(Track.delete_orphaned([track.id])).to eq(1)

    expect(component(2024)).not_to eq(before)
  end

  it 'bumps from Track#update_dominant_mode! despite update_column skipping callbacks' do
    track = build_track
    create(:track_segment, track:, transportation_mode: :driving, distance: 100, duration: 60)

    before = component(2024)
    track.update_dominant_mode!

    expect(component(2024)).not_to eq(before)
    expect(track.reload.dominant_mode).to eq('driving')
  end

  it 'bumps from a track reclassification despite update_column' do
    track = build_track
    create(:track_segment, track:, transportation_mode: :cycling, distance: 100, duration: 60,
                           corrected_at: Time.current)

    before = component(2024)
    TransportationModes::ReclassifyTrackJob.new.perform(track.id)

    expect(component(2024)).not_to eq(before)
    expect(track.reload.dominant_mode).to eq('cycling')
  end

  it 'bumps when the parallel generator wipes a user\'s tracks via destroy_all' do
    build_track
    before = component(2024)

    user.tracks.destroy_all

    expect(component(2024)).not_to eq(before)
  end

  it 'invalidates INTERIOR years of a multi-year track on update' do
    track = create(:track, user:,
                          start_at: Time.utc(2023, 12, 30), end_at: Time.utc(2025, 1, 2))
    before_2024 = component(2024)

    track.update!(distance: 999)

    expect(component(2024)).not_to eq(before_2024)
  end

  it 'invalidates INTERIOR years from delete_orphaned' do
    track = create(:track, user:,
                          start_at: Time.utc(2023, 12, 30), end_at: Time.utc(2025, 1, 2))
    before_2024 = component(2024)

    Track.delete_orphaned([track.id])

    expect(component(2024)).not_to eq(before_2024)
  end

  it 'bumps from TrackBuilder#update_dominant_mode despite update_column skipping callbacks' do
    track = build_track
    host = Class.new do
      include Tracks::TrackBuilder
      def initialize(user)
        @user = user
      end
      attr_reader :user
    end

    before = component(2024)
    host.new(user).update_dominant_mode(track, [{ mode: :driving, distance: 100, duration: 60 }])

    expect(component(2024)).not_to eq(before)
    expect(track.reload.dominant_mode).to eq('driving')
  end
end

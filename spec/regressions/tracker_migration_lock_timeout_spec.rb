# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Per-tracker migration lock contention' do
  let(:user) { create(:user) }
  let!(:track) do
    create(:track, user: user, tracker_id: nil, start_at: Time.utc(2025, 1, 1), end_at: Time.utc(2025, 1, 2))
  end
  let!(:point) do
    create(:point, user: user, track: track, timestamp: Time.utc(2025, 1, 1, 12).to_i,
                   tracker_id: 'google-maps-timeline-export', raw_data: { 'deviceTag' => 123 })
  end

  before do
    allow(Tracks::PerUserLock).to receive(:with_user_lock)
      .and_raise(Tracks::PerUserLock::AcquisitionTimeout, 'synthetic occupied lock')
  end

  it 'propagates lock failure to the migration instead of reporting success and retrying on stats' do
    expect do
      DataMigrations::RecalculatePerTrackerTracksJob.perform_now(user.id)
    end.to raise_error(Tracks::PerUserLock::AcquisitionTimeout)

    expect(Users::RecalculateDataJob).not_to have_been_enqueued
    expect(Track.exists?(track.id)).to be(true)
  end

  it 'still retries the rebuild after point IDs changed on the failed attempt' do
    track.update!(tracker_id: 'old-device')
    expect do
      DataMigrations::RecalculatePerTrackerTracksJob.perform_now(user.id)
    end.to raise_error(Tracks::PerUserLock::AcquisitionTimeout)
    expect(point.reload.tracker_id).to eq('google-records-device-123')

    allow(Tracks::PerUserLock).to receive(:with_user_lock).and_call_original
    expect do
      DataMigrations::RecalculatePerTrackerTracksJob.perform_now(user.id)
    end.to have_enqueued_job(Tracks::TimeChunkProcessorJob)
    expect(Track.exists?(track.id)).to be(false)
  end
end

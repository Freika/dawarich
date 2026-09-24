# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Retired per-tracker migration' do
  let(:user) { create(:user) }
  let!(:track) do
    create(:track, user: user, tracker_id: 'historical-device',
                   start_at: Time.utc(2025, 1, 1), end_at: Time.utc(2025, 1, 2))
  end
  let!(:point) do
    create(:point, user: user, track: track, timestamp: Time.utc(2025, 1, 1, 12).to_i,
                   tracker_id: 'google-maps-timeline-export', raw_data: { 'deviceTag' => 123 })
  end

  it 'does not mutate v2 points or tracks when an old migration enqueues it for a user' do
    original_source_id = point.source_id

    DataMigrations::RecalculatePerTrackerTracksJob.perform_now(user.id)

    expect(point.reload.source_id).to eq(original_source_id)
    expect(track.reload.tracker_id).to eq('historical-device')
    expect(Users::RecalculateDataJob).not_to have_been_enqueued
  end

  it 'does not enqueue a legacy table scan when an old migration enqueues it without a user' do
    DataMigrations::RecalculatePerTrackerTracksJob.perform_now

    expect(DataMigrations::RecalculatePerTrackerTracksJob).not_to have_been_enqueued
  end
end

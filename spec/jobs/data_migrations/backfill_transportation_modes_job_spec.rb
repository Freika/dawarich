# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillTransportationModesJob do
  it 'queues only active users tracks that lack segments or have an unknown mode' do
    user = create(:user)
    missing = create(:track, user:)
    unknown = create(:track, user:, dominant_mode: :unknown)
    create(:track_segment, track: unknown)
    known = create(:track, user:, dominant_mode: :driving)
    create(:track_segment, track: known)
    deleted_user = create(:user, deleted_at: Time.current)
    create(:track, user: deleted_user)

    described_class.perform_now

    queued_ids = enqueued_jobs.filter_map do |job|
      job[:args].first if job[:job] == TransportationModes::ReclassifyTrackJob
    end
    expect(queued_ids).to contain_exactly(missing.id, unknown.id)
  end

  it 'continues from the last track when a batch is full' do
    stub_const('DataMigrations::BackfillTransportationModesJob::BATCH_SIZE', 2)
    tracks = create_list(:track, 3, user: create(:user))

    described_class.perform_now

    expect(described_class).to have_been_enqueued.with(tracks.second.id)
    expect(TransportationModes::ReclassifyTrackJob).to have_been_enqueued.exactly(2).times

    clear_enqueued_jobs
    described_class.perform_now(tracks.second.id)

    expect(TransportationModes::ReclassifyTrackJob).to have_been_enqueued.with(tracks.third.id)
    expect(described_class).not_to have_been_enqueued
  end
end

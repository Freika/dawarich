# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::MapMatching::Enqueuer do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:track) do
    create(:track, user:, start_at: Time.zone.at(100), end_at: Time.zone.at(110),
                   original_path: 'LINESTRING(13.4 52.5, 13.41 52.51)')
  end

  before do
    allow(DawarichSettings).to receive_messages(map_matching_enabled?: true, atlas_url: 'http://atlas:4567')
    create(:point, user:, track:, timestamp: 100, longitude: 13.4, latitude: 52.5)
    create(:point, user:, track:, timestamp: 110, longitude: 13.41, latitude: 52.51)
    create(:track_segment, :anchored, track:, transportation_mode: :walking,
                                      start_at: Time.zone.at(100), end_at: Time.zone.at(110))
  end

  it 'claims a digest and enqueues exactly once for unchanged pending input' do
    expect { described_class.call(track) }.to have_enqueued_job(Tracks::MapMatchJob).once

    digest = track.reload.map_matching_input_digest
    expect(track).to be_map_matching_status_pending

    expect { described_class.call(track) }.not_to have_enqueued_job(Tracks::MapMatchJob)
    expect(track.reload.map_matching_input_digest).to eq(digest)
  end

  it 're-enqueues unchanged input when the previous claim went stale' do
    described_class.call(track)

    travel(2.hours) do
      expect { described_class.call(track) }.to have_enqueued_job(Tracks::MapMatchJob).once
    end
  end

  it 'claims without changing the track revision the map editor checks' do
    expect { described_class.call(track) }.not_to(change { track.reload.lock_version })
    expect(track).to be_map_matching_status_pending
  end

  it 'enqueues only after the surrounding transaction commits' do
    enqueued_inside_transaction = nil

    Track.transaction do
      described_class.call(track)
      enqueued_inside_transaction = enqueued_jobs.count { |job| job[:job] == Tracks::MapMatchJob }
    end

    expect(enqueued_inside_transaction).to eq(0)
    expect(Tracks::MapMatchJob).to have_been_enqueued.once
  end

  it 'does nothing when the global setting is off' do
    allow(DawarichSettings).to receive(:map_matching_enabled?).and_return(false)

    expect { described_class.call(track) }.not_to have_enqueued_job(Tracks::MapMatchJob)
    expect(track.reload.map_matching_status).to be_nil
  end

  it 'does not process demo tracks' do
    track.update!(demo: true)

    expect { described_class.call(track) }.not_to have_enqueued_job(Tracks::MapMatchJob)
  end

  it 'marks a track with no eligible modes as skipped without enqueueing' do
    track.track_segments.update_all(transportation_mode: TrackSegment.transportation_modes[:train])

    expect { described_class.call(track) }.not_to have_enqueued_job(Tracks::MapMatchJob)
    expect(track.reload).to be_map_matching_status_skipped
    expect(track.matched_path).to be_nil
  end

  it 're-enqueues when a segment mode changes' do
    described_class.call(track)
    first_digest = track.reload.map_matching_input_digest
    track.track_segments.first.update!(transportation_mode: :cycling)

    expect { described_class.call(track) }.to have_enqueued_job(Tracks::MapMatchJob).once
    expect(track.reload.map_matching_input_digest).not_to eq(first_digest)
  end
end

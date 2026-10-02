# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RailsCommands::Registry, 'release reverse-outbox kinds' do
  let(:run_at) { 1.hour.from_now.to_i }

  it 'release_reclassify_tracks enqueues one ReclassifyTrackJob per track at run_at' do
    handler = described_class.handler('release_reclassify_tracks')

    expect { handler.call({ 'user_id' => 7, 'track_ids' => [3, 4], 'run_at' => run_at }) }
      .to have_enqueued_job(TransportationModes::ReclassifyTrackJob).with(3).at(Time.zone.at(run_at))
      .and have_enqueued_job(TransportationModes::ReclassifyTrackJob).with(4).at(Time.zone.at(run_at))
  end

  it 'release_user_redetect enqueues UserRedetectJob at run_at' do
    handler = described_class.handler('release_user_redetect')

    expect { handler.call({ 'user_id' => 7, 'run_at' => run_at }) }
      .to have_enqueued_job(Visits::UserRedetectJob).with(7).at(Time.zone.at(run_at))
  end

  it 'release_null_island_follow_up replays the follow-up' do
    handler = described_class.handler('release_null_island_follow_up')
    user = create(:user)
    track = create(:track, user:)
    timestamp = Time.utc(2026, 3, 5, 12).to_i
    create(:point, user:, track:, longitude: 0.01, latitude: 0.01, timestamp:, anomaly: true)
    visit = create(:visit, user:, place: create(:place, latitude: 0.02, longitude: 0.02, lonlat: 'POINT(0.02 0.02)'))
    allow(Points::TileEpoch).to receive(:bump).and_call_original

    expect { handler.call({ 'user_id' => user.id }) }
      .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2026, 3)
      .and have_enqueued_job(Tracks::RecalculateJob).with(track.id)
    expect(Visit.exists?(visit.id)).to be(false)
    expect(Points::TileEpoch).to have_received(:bump).with(user.id, timestamps: [timestamp])
  end

  it 'release_null_island_follow_up skips a missing user' do
    handler = described_class.handler('release_null_island_follow_up')

    expect { handler.call({ 'user_id' => 0 }) }.not_to have_enqueued_job
  end
end

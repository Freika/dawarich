# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Point move outcome after commit', :non_transactional do
  it 'publishes a committed move and schedules stats despite slow cache invalidation' do
    user = create(:user)
    track = create(:track, user:, start_at: Time.zone.at(1_000), end_at: Time.zone.at(1_120),
                           original_path: 'LINESTRING(0 0, 0.02 0)')
    point = create(:point, user:, track:, timestamp: 1_000, longitude: 0, latitude: 0)
    create(:point, user:, track:, timestamp: 1_120, longitude: 0.02, latitude: 0)
    stub_const('Points::Move::TIMEOUT_SECONDS', 1)
    allow(Tracks::TileEpoch).to receive(:bump_range).and_wrap_original do |method, *args|
      sleep 1.1
      method.call(*args)
    end
    allow(MapEditsChannel).to receive(:broadcast_to)

    result = nil
    expect do
      result = Points::Move.call(
        user:, point_id: point.id, latitude: 0.01, longitude: 0.01,
        point_revision: point.lock_version, track_revision: track.lock_version,
        history_scope: { start_at: 900, end_at: 1_200 }
      )
    end.to have_enqueued_job(Stats::CalculatingJob).with(user.id, 1970, 1)

    expect(result.point).to have_attributes(lon: 0.01, lat: 0.01, lock_version: 1)
    expect(point.reload).to have_attributes(lon: 0.01, lat: 0.01, lock_version: 1)
    expect(MapEditsChannel).to have_received(:broadcast_to).with(
      user, hash_including(type: 'point_moved', data: hash_including(revision: { point: 1, track: 1 }))
    )
  end
end

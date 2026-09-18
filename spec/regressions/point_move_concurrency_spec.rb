# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Point moves on the same Track', :non_transactional, threads: 2 do
  it 'serializes both transactions and rejects the stale contender' do
    user = create(:user)
    track = create(
      :track,
      user: user,
      start_at: Time.zone.at(1_000),
      end_at: Time.zone.at(1_120),
      original_path: 'LINESTRING(0 0, 0.02 0)'
    )
    point = create(:point, user: user, track: track, timestamp: 1_000, longitude: 0, latitude: 0)
    create(:point, user: user, track: track, timestamp: 1_120, longitude: 0.02, latitude: 0)
    allow(MapEdits::Publisher).to receive(:call)

    ready = Concurrent::CountDownLatch.new(2)
    start = Concurrent::CountDownLatch.new(1)
    outcomes = Concurrent::Array.new
    coordinates = [[0.005, 0.006], [0.007, 0.008]]
    threads = coordinates.map do |longitude, latitude|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready.count_down
          start.wait
          begin
            result = Points::Move.call(
              user: User.find(user.id),
              point_id: point.id,
              latitude: latitude,
              longitude: longitude,
              point_revision: 0,
              track_revision: 0,
              history_scope: { start_at: 900, end_at: 1_200 }
            )
            outcomes << [:success, result.point.lon, result.point.lat]
          rescue Points::Move::StaleEdit => e
            outcomes << [:stale, e.result.point.lon, e.result.point.lat]
          end
        end
      end
    end

    expect(ready.wait(5)).to be(true)
    start.count_down
    Timeout.timeout(15) { threads.each(&:join) }

    expect(outcomes.map(&:first).sort).to eq(%i[stale success])
    winner = outcomes.find { |outcome| outcome.first == :success }
    stale = outcomes.find { |outcome| outcome.first == :stale }
    expect(stale.drop(1)).to eq(winner.drop(1))
    expect(point.reload).to have_attributes(lon: winner[1], lat: winner[2], lock_version: 1)
    expect(track.reload.lock_version).to eq(1)
  ensure
    start&.count_down
    threads&.each { |thread| thread.kill if thread.alive? }
    threads&.each(&:join)
  end
end

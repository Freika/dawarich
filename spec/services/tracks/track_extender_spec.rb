# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::TrackExtender, :non_transactional do
  let(:anchor) { Time.utc(2025, 2, 12, 10) }
  let(:user) { create(:user) }
  let(:track) { create(:track, user: user, start_at: anchor, end_at: anchor + 600) }
  let!(:tracked) { create(:point, user: user, track: track, timestamp: anchor.to_i, lonlat: 'POINT(13.40 52.52)') }
  let!(:late) { create(:point, user: user, timestamp: (anchor + 900).to_i, lonlat: 'POINT(13.41 52.52)') }
  let!(:other) { create(:point, user: user, timestamp: (anchor + 1800).to_i, lonlat: 'POINT(13.42 52.52)') }

  after do
    connection = ActiveRecord::Base.connection
    %w[point_revisions track_revisions].each { |t| connection.execute("DELETE FROM #{t} WHERE user_id = #{user.id}") }
    Point.where(user_id: user.id).delete_all
    TrackSegment.where(track_id: Track.where(user_id: user.id).select(:id)).delete_all
    Track.where(user_id: user.id).delete_all
    user.delete
  end

  def in_thread(&)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&) }
  end

  # pg_stat_activity is snapshotted per transaction, so clear it on every poll.
  def wait_for_lock_waiter
    Timeout.timeout(5) do
      sleep 0.05 until ActiveRecord::Base.connection.select_value(<<~SQL.squish).positive?
        SELECT count(*) FROM (SELECT pg_stat_clear_snapshot()) AS cleared, pg_stat_activity
        WHERE datname = current_database() AND wait_event_type = 'Lock'
      SQL
    end
  end

  # A chunk building a new track writes track revisions before point revisions;
  # extending a track in a concurrent chunk must take them in the same order.
  it 'bumps revisions in the track-builder order so concurrent chunks cannot deadlock' do
    builder_holds_track_revision = Queue.new
    builder = in_thread do |connection|
      connection.transaction do
        create(:track, user: user, start_at: anchor + 3600, end_at: anchor + 3660)
        builder_holds_track_revision << true
        wait_for_lock_waiter
        connection.execute("UPDATE points SET track_id = track_id WHERE id = #{other.id}")
      end
      :committed
    rescue ActiveRecord::Deadlocked
      :deadlocked
    end
    Timeout.timeout(5) { builder_holds_track_revision.pop }

    extender = in_thread do
      track.with_lock { described_class.new(user, track).extend_with([late]) }
      :committed
    rescue ActiveRecord::Deadlocked
      :deadlocked
    end

    expect([builder.value, extender.value]).to eq(%i[committed committed])
    expect(late.reload.track_id).to eq(track.id)
    expect(track.reload.end_at).to eq(Time.zone.at(late.timestamp))
  end

  # A boundary merge can hand over a track whose points were all deleted.
  it 'refreshes the track in place when there are no points to move' do
    create(:point, user: user, track: track, timestamp: (anchor + 600).to_i, lonlat: 'POINT(13.405 52.52)')

    expect { track.with_lock { described_class.new(user, track).extend_with([]) } }.not_to raise_error
    expect(track.reload.start_at).to eq(anchor)
  end
end

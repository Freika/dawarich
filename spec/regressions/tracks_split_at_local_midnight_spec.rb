# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tracks split at local midnight' do
  include ActiveSupport::Testing::TimeHelpers

  # Local midnight in Berlin (CET) is 23:00 UTC, so a split at UTC midnight
  # would leave the walk below in one track.
  let(:start_timestamp) { Time.utc(2025, 1, 14, 22, 30).to_i }
  let(:local_midnight) { Time.utc(2025, 1, 14, 23) }
  let(:rows) { (0..60).map { |minute| [minute, -140.0 + minute * 0.0015] } }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
  end

  context 'when the user splits tracks at midnight' do
    let(:user) { night_user('split_tracks_at_midnight' => true) }

    it 'ends the track at the last point before local midnight in bulk generation' do
      feed = rows.map { |minute, lon| create_night_point(user, minute, lon) }

      process_bulk(user, feed)

      expect_split_at_local_midnight(user, feed)
    end

    it 'keeps the halves apart when realtime points arrive one at a time' do
      feed = rows.map do |minute, lon|
        travel_to(Time.zone.at(start_timestamp + minute * 60)) do
          point = create_night_point(user, minute, lon)
          Tracks::IncrementalGenerator.new(user).call
          point
        end
      end

      expect_split_at_local_midnight(user, feed)
    end

    it 'splits a realtime batch uploaded after midnight' do
      feed = rows.map { |minute, lon| create_night_point(user, minute, lon) }

      travel_to(Time.zone.at(feed.last.timestamp + 60)) { Tracks::IncrementalGenerator.new(user).call }

      expect_split_at_local_midnight(user, feed)
    end
  end

  context 'when the setting is left at its default' do
    let(:user) { night_user }

    it 'keeps a walk across midnight in one track' do
      feed = rows.map { |minute, lon| create_night_point(user, minute, lon) }

      process_bulk(user, feed)

      expect(feed.first.reload.track_id).to be_present
      expect(feed.last.reload.track_id).to eq(feed.first.track_id)
    end
  end

  def night_user(extra_settings = {})
    create(:user, settings: { 'timezone' => 'Europe/Berlin', 'minutes_between_routes' => 30 }.merge(extra_settings))
  end

  def create_night_point(owner, minute, lon)
    create(:point, user: owner, tracker_id: 'synthetic-night-walk',
                   timestamp: start_timestamp + minute * 60, lonlat: "POINT(#{lon} -40.0)")
  end

  def expect_split_at_local_midnight(owner, feed)
    before_midnight = feed[29].reload.track
    after_midnight = feed[30].reload.track

    expect(before_midnight).to be_present
    expect(after_midnight).to be_present
    expect(after_midnight.id).not_to eq(before_midnight.id)
    expect(before_midnight.end_at.to_i).to eq(feed[29].timestamp)
    expect(after_midnight.start_at.to_i).to eq(feed[30].timestamp)
    expect(owner.tracks.where('start_at < :midnight AND end_at >= :midnight', midnight: local_midnight)).to be_empty
  end

  def process_bulk(owner, feed)
    chunk = {
      chunk_id: SecureRandom.uuid,
      start_timestamp: start_timestamp, end_timestamp: feed.last.timestamp,
      buffer_start_timestamp: start_timestamp, buffer_end_timestamp: feed.last.timestamp
    }
    session = Tracks::SessionManager.create_for_user(owner.id)
    session.mark_started(1)
    travel_to(Time.zone.at(feed.last.timestamp)) do
      Tracks::TimeChunkProcessorJob.perform_now(owner.id, session.session_id, chunk)
      Tracks::BoundaryDetector.new(owner).resolve_cross_chunk_tracks
    end
    session.cleanup_session
  end
end

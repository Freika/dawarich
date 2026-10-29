# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tracks split at visits shorter than the route gap' do
  include ActiveSupport::Testing::TimeHelpers

  let(:start_timestamp) { Time.utc(2025, 2, 10, 9).to_i }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
  end

  context 'with the default 30-minute route gap and 5-minute visits' do
    let(:user) { stop_user }

    it 'ends the arrival track at a 10-minute stop in bulk generation' do
      feed = stop_rows(10).map { |minute, lon| create_stop_point(user, minute, lon) }

      process_bulk(user, feed)

      expect_split_at_stop(feed, 10)
    end

    it 'ends the arrival track at a 10-minute stop in realtime generation' do
      feed = stop_rows(10).map do |minute, lon|
        travel_to(Time.zone.at(start_timestamp + minute * 60)) do
          point = create_stop_point(user, minute, lon)
          Tracks::IncrementalGenerator.new(user).call
          point
        end
      end

      expect_split_at_stop(feed[0...-10], 10)
    end

    it 'keeps a 3-minute stop inside one track' do
      feed = stop_rows(3).map { |minute, lon| create_stop_point(user, minute, lon) }

      process_bulk(user, feed)

      expect(feed.first.reload.track_id).to be_present
      expect(feed.last.reload.track_id).to eq(feed.first.track_id)
    end

    it 'shows separate journeys around the visit on the timeline' do
      feed = stop_rows(10).map { |minute, lon| create_stop_point(user, minute, lon) }
      process_bulk(user, feed)
      create(:visit, user: user, name: 'Synthetic stop', status: :confirmed,
                     started_at: Time.zone.at(feed[30].timestamp), ended_at: Time.zone.at(feed[40].timestamp),
                     duration: 10)

      day = Time.zone.at(start_timestamp)
      entries = Timeline::DayAssembler.new(user, start_at: day.beginning_of_day.iso8601,
                                                 end_at: day.end_of_day.iso8601).call.first[:entries]

      expect(entries.map { |entry| entry[:type] }).to eq(%w[journey visit journey])
    end
  end

  context 'with a logger that reports every 15 minutes while stationary' do
    let(:user) { stop_user }
    let(:rows) do
      stop_lon = -140.0 + 30 * 0.0015
      (0..30).map { |minute| [minute, -140.0 + minute * 0.0015] } +
        (1..8).map { |ping| [30 + ping * 15, stop_lon] } +
        (1..30).map { |step| [150 + step, stop_lon + step * 0.0015] }
    end

    it 'still ends the arrival track at a two-hour stop in bulk generation' do
      feed = rows.map { |minute, lon| create_stop_point(user, minute, lon) }

      process_bulk(user, feed)

      expect(feed.first.reload.track_id).to be_present
      expect(feed.last.reload.track_id).to be_present
      expect(feed.last.track_id).not_to eq(feed.first.track_id)
    end

    it 'still ends the arrival track at a two-hour stop in realtime generation' do
      feed = rows.map do |minute, lon|
        travel_to(Time.zone.at(start_timestamp + minute * 60)) do
          point = create_stop_point(user, minute, lon)
          Tracks::IncrementalGenerator.new(user).call
          point
        end
      end

      expect(feed.first.reload.track_id).to be_present
      expect(feed[-2].reload.track_id).to be_present
      expect(feed[-2].track_id).not_to eq(feed.first.track_id)
      expect(feed.first.track.end_at.to_i).to eq(feed[30].timestamp)
    end
  end

  it 'keeps a slow walk in one track when visits need only 1 minute' do
    user = stop_user('visit_min_duration_minutes' => 1)
    feed = (0..180).map do |step|
      create(:point, user: user, tracker_id: 'synthetic-short-visit', timestamp: start_timestamp + step * 10,
                     lonlat: "POINT(#{-140.0 + step * 0.00015} -40.0)")
    end

    process_bulk(user, feed)

    expect(feed.first.reload.track_id).to be_present
    expect(feed.map { |point| point.reload.track_id }.uniq).to eq([feed.first.track_id])
  end

  it 'keeps a 10-minute stop inside one track when visits need 15 minutes' do
    user = stop_user('visit_min_duration_minutes' => 15)
    feed = stop_rows(10).map { |minute, lon| create_stop_point(user, minute, lon) }

    process_bulk(user, feed)

    expect(feed.first.reload.track_id).to be_present
    expect(feed.last.reload.track_id).to eq(feed.first.track_id)
  end

  def stop_user(extra_settings = {})
    create(:user, settings: { 'timezone' => 'UTC', 'minutes_between_routes' => 30 }.merge(extra_settings))
  end

  # Thirty minutes of walking, a stop reported every minute, thirty more minutes of walking.
  # The coordinates are made up, in the South Pacific.
  def stop_rows(stop_minutes)
    stop_lon = -140.0 + 30 * 0.0015
    (0..30).map { |minute| [minute, -140.0 + minute * 0.0015] } +
      (31..(30 + stop_minutes)).map { |minute| [minute, stop_lon] } +
      (1..30).map { |step| [30 + stop_minutes + step, stop_lon + step * 0.0015] }
  end

  def create_stop_point(owner, minute, lon)
    create(:point, user: owner, tracker_id: 'synthetic-short-visit',
                   timestamp: start_timestamp + minute * 60, lonlat: "POINT(#{lon} -40.0)")
  end

  def expect_split_at_stop(feed, stop_minutes)
    arrival_track = feed.first.reload.track
    departure_track = feed.last.reload.track

    expect(arrival_track).to be_present
    expect(departure_track).to be_present
    expect(departure_track.id).not_to eq(arrival_track.id)
    expect(arrival_track.end_at.to_i).to eq(feed[30].timestamp)
    expect(departure_track.start_at.to_i).to eq(feed[30 + stop_minutes].timestamp)
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

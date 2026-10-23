# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Continuous tracking ends tracks at overnight stops' do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, settings: { 'minutes_between_routes' => 30, 'meters_between_routes' => 500 })
  end
  let(:start_timestamp) { Time.utc(2025, 2, 10, 18).to_i }
  let(:points) do
    # Two one-hour journeys separated by a 23-hour stop. The same device
    # continues reporting every five minutes, including while stationary.
    # These made-up coordinates are in the South Pacific, away from homes.
    (0..300).map { |index| create_feed_point(index) }
  end
  let(:realtime_feed) do
    # One extra moving report completes the final two-point realtime batch.
    (0..301).map do |index|
      travel_to(Time.zone.at(start_timestamp + index * 5.minutes.to_i)) do
        point = create_feed_point(index)
        Tracks::IncrementalGenerator.new(user).call
        point
      end
    end
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
  end

  it 'assigns the journeys before and after the stop to different tracks during bulk generation' do
    session = instance_double(Tracks::SessionManager, session_exists?: true,
                                                     increment_completed_chunks: true,
                                                     increment_tracks_created: true)
    allow(Tracks::SessionManager).to receive(:new).with(user.id, 'synthetic-session').and_return(session)
    points

    chunk = {
      chunk_id: 'synthetic-chunk',
      start_timestamp: start_timestamp,
      end_timestamp: points.last.timestamp,
      buffer_start_timestamp: start_timestamp,
      buffer_end_timestamp: points.last.timestamp
    }
    Tracks::TimeChunkProcessorJob.perform_now(user.id, 'synthetic-session', chunk)

    first_track_id = points.first.reload.track_id
    last_track_id = points.last.reload.track_id
    expect(first_track_id).to be_present
    expect(last_track_id).to be_present
    expect(last_track_id).not_to eq(first_track_id),
                                 'A stationary overnight heartbeat must not join two journeys into one 25-hour track'
  end

  it 'separates the journeys in SQL segmentation of the full feed' do
    segments = Track.get_segments_with_points(user.id, start_timestamp, points.last.timestamp, 30)
    first_segment = segments.find { |segment| segment[:points].any? { |point| point.id == points.first.id } }
    last_segment = segments.find { |segment| segment[:points].any? { |point| point.id == points.last.id } }

    expect(first_segment).to be_present
    expect(last_segment).to be_present
    expect(last_segment[:start_timestamp]).not_to eq(first_segment[:start_timestamp]),
                                                  'Continuous stationary reports must not erase the journey boundary'
  end

  it 'ends the arrival track when realtime points arrive one at a time throughout the overnight stop' do
    feed = realtime_feed

    arrival_track = feed.first.reload.track
    departure_track = feed.last.reload.track
    expect(arrival_track).to be_present
    expect(departure_track).to be_present
    expect(departure_track.id).not_to eq(arrival_track.id)
    expect(arrival_track.end_at.to_i).to eq(feed[12].timestamp)
    expect(feed[13..287].map { |point| point.reload.track_id }).to all(be_nil)
    expect(departure_track.start_at.to_i).to eq(feed[288].timestamp)
  end

  it 'detects a visit at the overnight stop after realtime track generation' do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
    feed = realtime_feed

    expect(feed.first.reload.track_id).to be_present
    expect(feed.last.reload.track_id).to be_present
    expect(feed.last.track_id).not_to eq(feed.first.track_id)
    expect(user.tracks.joins(:track_segments)).to be_present

    visits = Visits::Detection::Runner.new(user, start_at: start_timestamp, end_at: feed.last.timestamp).call

    expect(visits.size).to eq(1)
    visit = visits.first.reload
    expect(visit).to be_suggested
    expect(visit.detection_version).to eq(Visits::Detection::VERSION)
    expect(visit.started_at.to_i).to be_within(15.minutes.to_i).of(feed[12].timestamp)
    expect(visit.ended_at.to_i).to be_within(15.minutes.to_i).of(feed[288].timestamp)
    expect(visit.center[0]).to be_within(0.0001).of(-40.0)
    expect(visit.center[1]).to be_within(0.0001).of(-139.976)
    expect(feed[19..287].map { |point| point.reload.visit_id }).to all(eq(visit.id))
  end

  [[15, 20], [10, 25], [30, 40]].each do |threshold, stop_minutes|
    context "with a #{stop_minutes}-minute stop and a #{threshold}-minute threshold" do
      it 'keeps the journeys apart after the boundary merge in bulk generation' do
        stop_user = short_stop_user(threshold)
        feed = short_stop_rows(stop_minutes).map { |minute, lon| create_short_stop_point(stop_user, minute, lon) }

        process_bulk(stop_user, feed)

        expect(feed.first.reload.track_id).to be_present
        expect(feed.last.reload.track_id).to be_present
        expect(feed.last.track_id).not_to eq(feed.first.track_id)
      end

      it 'keeps the journeys apart and ends the arrival track at the arrival in realtime generation' do
        stop_user = short_stop_user(threshold)
        feed = feed_in_realtime(stop_user, short_stop_rows(stop_minutes))
        arrival_track = feed.first.reload.track
        departure_track = feed[-10].reload.track

        expect(arrival_track).to be_present
        expect(departure_track).to be_present
        expect(departure_track.id).not_to eq(arrival_track.id)
        expect(arrival_track.end_at.to_i).to eq(feed[30].timestamp)
        expect(feed[31...(30 + stop_minutes)].map { |point| point.reload.track_id }).to all(be_nil)
        expect(departure_track.start_at.to_i).to eq(feed[30 + stop_minutes].timestamp)
      end
    end
  end

  it 'keeps a stop shorter than the threshold inside one track in bulk and realtime generation' do
    bulk_user = short_stop_user(30)
    bulk_feed = short_stop_rows(10).map { |minute, lon| create_short_stop_point(bulk_user, minute, lon) }
    process_bulk(bulk_user, bulk_feed)

    realtime_feed = feed_in_realtime(short_stop_user(30), short_stop_rows(10))

    expect(bulk_feed.last.reload.track_id).to be_present
    expect(bulk_feed.last.track_id).to eq(bulk_feed.first.reload.track_id)
    expect(realtime_feed[-10].reload.track_id).to be_present
    expect(realtime_feed[-10].track_id).to eq(realtime_feed.first.reload.track_id)
  end

  def short_stop_user(threshold)
    create(:user, settings: { 'minutes_between_routes' => threshold, 'meters_between_routes' => 500 })
  end

  # Thirty minutes of walking, a stop at the last walking position reported every
  # minute, and thirty more minutes of walking.
  def short_stop_rows(stop_minutes)
    stop_lon = -140.0 + 30 * 0.0015
    (0..30).map { |minute| [minute, -140.0 + minute * 0.0015] } +
      (31..(30 + stop_minutes)).map { |minute| [minute, stop_lon] } +
      (1..30).map { |step| [30 + stop_minutes + step, stop_lon + step * 0.0015] }
  end

  def create_short_stop_point(stop_user, minute, lon)
    create(:point, user: stop_user, tracker_id: 'synthetic-short-stop',
                   timestamp: start_timestamp + minute * 60, lonlat: "POINT(#{lon} -40.0)")
  end

  def process_bulk(stop_user, feed)
    chunk = {
      chunk_id: SecureRandom.uuid,
      start_timestamp: start_timestamp, end_timestamp: feed.last.timestamp,
      buffer_start_timestamp: start_timestamp, buffer_end_timestamp: feed.last.timestamp
    }
    session = Tracks::SessionManager.create_for_user(stop_user.id)
    session.mark_started(1)
    travel_to(Time.zone.at(feed.last.timestamp)) do
      Tracks::TimeChunkProcessorJob.perform_now(stop_user.id, session.session_id, chunk)
      Tracks::BoundaryDetector.new(stop_user).resolve_cross_chunk_tracks
    end
    session.cleanup_session
  end

  def feed_in_realtime(stop_user, rows)
    rows.map do |minute, lon|
      travel_to(Time.zone.at(start_timestamp + minute * 60)) do
        point = create_short_stop_point(stop_user, minute, lon)
        Tracks::IncrementalGenerator.new(stop_user).call
        point
      end
    end
  end

  def create_feed_point(index)
    step = if index <= 12
             index
           elsif index <= 288
             12
           else
             12 + index - 288
           end

    create(:point, user: user, tracker_id: 'synthetic-continuous-feed',
                   timestamp: start_timestamp + index * 5.minutes.to_i,
                   lonlat: "POINT(#{-140.0 + step * 0.002} -40.0)",
                   velocity: step == 12 ? 0 : 2, accuracy: 5,
                   reverse_geocoded_at: Time.current)
  end
end

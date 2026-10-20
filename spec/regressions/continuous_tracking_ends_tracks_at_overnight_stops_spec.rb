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
    segments = Track.get_segments_with_points(user.id, start_timestamp, points.last.timestamp, 30, 500)
    first_segment = segments.find { |segment| segment[:points].any? { |point| point.id == points.first.id } }
    last_segment = segments.find { |segment| segment[:points].any? { |point| point.id == points.last.id } }

    expect(first_segment).to be_present
    expect(last_segment).to be_present
    expect(last_segment[:start_timestamp]).not_to eq(first_segment[:start_timestamp]),
                                                  'Continuous stationary reports must not erase the journey boundary'
  end

  it 'ends the arrival track when realtime points arrive one at a time throughout the overnight stop' do
    # One extra moving report completes the final two-point realtime batch.
    feed = (0..301).map do |index|
      travel_to(Time.zone.at(start_timestamp + index * 5.minutes.to_i)) do
        point = create_feed_point(index)
        Tracks::IncrementalGenerator.new(user).call
        point
      end
    end

    arrival_track = feed.first.reload.track
    departure_track = feed.last.reload.track
    expect(arrival_track).to be_present
    expect(departure_track).to be_present
    expect(departure_track.id).not_to eq(arrival_track.id)
    # Realtime cannot recognize a long stop before the dwell threshold is reached.
    expect(arrival_track.end_at.to_i).to be_between(feed[12].timestamp, feed[18].timestamp)
    expect(feed[19..287].map { |point| point.reload.track_id }).to all(be_nil)
    expect(departure_track.start_at.to_i).to eq(feed[288].timestamp)
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

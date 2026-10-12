# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BoundaryDetector do
  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500
           })
  end
  let(:detector) { described_class.new(user) }
  let(:tracker) { 'device-1' }
  let(:base_time) { 1.hour.ago }

  def make_track_with_points(start_offset:, end_offset:, lng:, lat:)
    track = create(:track, user: user, tracker_id: tracker,
                           start_at: base_time + start_offset.seconds,
                           end_at: base_time + end_offset.seconds,
                           created_at: 2.minutes.ago)
    create(:point, user: user, tracker_id: tracker,
                   timestamp: (base_time + start_offset.seconds).to_i,
                   lonlat: "POINT(#{lng} #{lat})",
                   track: track)
    create(:point, user: user, tracker_id: tracker,
                   timestamp: (base_time + end_offset.seconds).to_i,
                   lonlat: "POINT(#{lng + 0.001} #{lat + 0.001})",
                   track: track)
    track
  end

  it 'refuses to merge two same-tracker tracks separated by more than the GPS-jump cap' do
    # Track 1 in Berlin (~52.52, 13.40), track 2 in Munich (~48.13, 11.58) — ~500 km
    berlin_track = make_track_with_points(start_offset: 0, end_offset: 60,
                                          lng: 13.40, lat: 52.52)
    munich_track = make_track_with_points(start_offset: 120, end_offset: 180,
                                          lng: 11.58, lat: 48.13)

    detector.resolve_cross_chunk_tracks

    expect(Track.exists?(berlin_track.id)).to be true
    expect(Track.exists?(munich_track.id)).to be true
    expect(user.tracks.count).to eq(2)
  end
end

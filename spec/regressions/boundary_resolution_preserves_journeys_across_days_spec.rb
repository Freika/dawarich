# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Boundary resolution preserves journeys across days' do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) do
    create(:user, settings: { 'minutes_between_routes' => 10, 'meters_between_routes' => 500 })
  end

  it 'does not merge a previous-day excursion into the next day across gaps longer than the route threshold' do
    travel_to(Time.utc(2026, 6, 15, 12)) do
      # Made-up positions in the open South Pacific. Only the first journey
      # visits longitude -140.5; the following day stays near -140.0.
      start_at = Time.utc(2026, 6, 12, 23, 30)
      samples = [
        [0, -140.5], [5, -140.25], [10, -140.0],
        [30, -139.998], [35, -139.99], [40, -140.0],
        [60, -139.998], [65, -140.01], [70, -140.0]
      ]
      points = samples.map do |minutes, longitude|
        create(:point, user: user, tracker_id: 'google-phone-synthetic',
                       timestamp: (start_at + minutes.minutes).to_i,
                       lonlat: "POINT(#{longitude} -40.0)")
      end
      session = instance_double(Tracks::SessionManager, session_exists?: true,
                                                       increment_completed_chunks: true,
                                                       increment_tracks_created: true)
      allow(Tracks::SessionManager).to receive(:new).with(user.id, 'synthetic-session').and_return(session)
      chunk = {
        chunk_id: 'synthetic-chunk',
        start_timestamp: points.first.timestamp, end_timestamp: points.last.timestamp,
        buffer_start_timestamp: points.first.timestamp, buffer_end_timestamp: points.last.timestamp
      }

      Tracks::TimeChunkProcessorJob.perform_now(user.id, 'synthetic-session', chunk)

      expect(user.tracks.count).to eq(3)
      expect(points.map { |point| point.reload.track_id }).not_to include(nil)
      expect(points.map { |point| [point.timestamp, point.lonlat.x] }).to eq(
        samples.map { |minutes, longitude| [(start_at + minutes.minutes).to_i, longitude] }
      )

      Tracks::BoundaryDetector.new(user).resolve_cross_chunk_tracks

      expect(user.tracks.count).to eq(3),
                                   'Boundary resolution must preserve 20-minute gaps with a 10-minute route threshold'
      expect(points.last.reload.track_id).not_to eq(points.first.reload.track_id)
      expect(user.tracks.maximum(:duration)).to eq(10.minutes.to_i)
    end
  end
end

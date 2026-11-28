# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Historical track catch-up preserves a continuous journey' do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, settings: { 'minutes_between_routes' => 30, 'meters_between_routes' => 500 }) }
  let(:anchor) { Time.utc(2025, 2, 12, 10) }
  let(:chunk) do
    {
      chunk_id: 'synthetic-catchup',
      start_timestamp: anchor.to_i,
      end_timestamp: (anchor + 1.hour).to_i,
      buffer_start_timestamp: anchor.to_i,
      buffer_end_timestamp: (anchor + 1.hour).to_i
    }
  end

  it 'adds a late historical point to the route instead of repeatedly leaving its section undrawn' do
    travel_to(anchor + 2.days) do
      session = Tracks::SessionManager.create_for_user(user.id)
      begin
        initial_points = 2.times.map do |index|
          create(:point, user: user, tracker_id: 'synthetic-device', anomaly: false,
                         timestamp: (anchor + index * 10.minutes).to_i,
                         lonlat: "POINT(#{-140 + index * 0.2} -40)")
        end
        Tracks::TimeChunkProcessorJob.perform_now(user.id, session.session_id, chunk)
        original_track = initial_points.first.reload.track
        expect(original_track).to be_present
        expect(initial_points.last.reload.track_id).to eq(original_track.id)

        late_point = create(:point, user: user, tracker_id: 'synthetic-device', anomaly: false,
                                    timestamp: (anchor + 20.minutes).to_i, lonlat: 'POINT(-139.6 -39.9)',
                                    created_at: 2.minutes.ago)
        2.times do
          Tracks::TimeChunkProcessorJob.perform_now(user.id, session.session_id, chunk.merge(untracked_only: true))
          Tracks::BoundaryDetector.new(user).resolve_cross_chunk_tracks
        end

        expect(late_point.reload.track_id).to eq(original_track.id)
        expect(original_track.reload.original_path.points.map { |point| [point.x, point.y] })
          .to include([-139.6, -39.9])
      ensure
        session.cleanup_session
      end
    end
  end
end

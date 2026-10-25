# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Track catch-up around an existing track' do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, settings: { 'minutes_between_routes' => 30, 'meters_between_routes' => 500 }) }
  let(:anchor) { Time.utc(2025, 2, 12, 10) }
  let(:chunk) do
    {
      chunk_id: 'synthetic-catchup',
      start_timestamp: (anchor - 1.hour).to_i,
      end_timestamp: (anchor + 1.hour).to_i,
      buffer_start_timestamp: (anchor - 1.hour).to_i,
      buffer_end_timestamp: (anchor + 1.hour).to_i
    }
  end

  def point_at(minutes, created_at: Time.current)
    create(:point, user: user, tracker_id: 'synthetic-device', anomaly: false,
                   timestamp: (anchor + minutes.minutes).to_i,
                   lonlat: "POINT(#{-140 + (minutes * 0.01)} -40)", created_at: created_at)
  end

  it 'tracks late points on both sides without a track that spans the existing one' do
    travel_to(anchor + 2.days) do
      session = Tracks::SessionManager.create_for_user(user.id)
      begin
        tracked = [point_at(0), point_at(10)]
        Tracks::TimeChunkProcessorJob.perform_now(user.id, session.session_id, chunk)
        existing_track = tracked.first.reload.track
        expect(existing_track).to be_present

        late = [point_at(-20), point_at(-10), point_at(20), point_at(30)].each do |point|
          point.update_columns(created_at: 2.minutes.ago)
        end
        Tracks::TimeChunkProcessorJob.perform_now(user.id, session.session_id, chunk.merge(untracked_only: true))
        Tracks::BoundaryDetector.new(user).resolve_cross_chunk_tracks

        expect((tracked + late).map { |point| point.reload.track_id }).to all(be_present)

        spans = user.tracks.reload.map { |track| [track.start_at, track.end_at] }.sort
        spans.each_cons(2) do |(_, earlier_end), (later_start, _)|
          expect(later_start).to be >= earlier_end
        end
      ensure
        session.cleanup_session
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Late points interleaved with an existing track' do
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

  def point_at(minutes)
    create(:point, user: user, tracker_id: 'synthetic-device', anomaly: false,
                   timestamp: (anchor + minutes.minutes).to_i,
                   lonlat: "POINT(#{-140 + (minutes * 0.001)} -40)")
  end

  it 'joins every late point to the track and rebuilds the track once' do
    travel_to(anchor + 2.days) do
      session = Tracks::SessionManager.create_for_user(user.id)
      begin
        tracked = (0..50).step(10).map { |minutes| point_at(minutes) }
        Tracks::TimeChunkProcessorJob.perform_now(user.id, session.session_id, chunk)
        track = tracked.first.reload.track

        late = [5, 15, 25, 35, 45].map { |minutes| point_at(minutes) }
        Point.where(id: late.map(&:id)).update_all(created_at: 2.minutes.ago)
        allow(Tracks::Reprocessor).to receive(:reprocess).and_call_original

        Tracks::TimeChunkProcessorJob.perform_now(user.id, session.session_id, chunk.merge(untracked_only: true))

        expect(late.map { |point| point.reload.track_id }).to all(eq(track.id))
        expect(Tracks::Reprocessor).to have_received(:reprocess).once
      ensure
        session.cleanup_session
      end
    end
  end
end

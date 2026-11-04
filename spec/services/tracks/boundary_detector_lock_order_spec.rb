# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BoundaryDetector, :non_transactional do
  include RevisionLockHelpers

  let(:user) { create(:user, settings: { 'minutes_between_routes' => 30, 'meters_between_routes' => 500 }) }
  let(:start) { 1.year.ago.utc.beginning_of_month + 10.days + 10.hours }
  let(:path) { 'LINESTRING(-74.0060 40.7128, -74.0070 40.7130)' }
  let!(:route) do
    create(:track, user: user, tracker_id: 'phone', start_at: start + 5.minutes, end_at: start + 15.minutes,
                   created_at: 2.days.ago, original_path: path)
  end
  let!(:batch) do
    create(:track, user: user, tracker_id: 'phone', start_at: start, end_at: start + 20.minutes,
                   created_at: 1.minute.ago, original_path: path)
  end
  let!(:untracked) do
    create(:point, user: user, tracker_id: 'phone', timestamp: (start + 3.hours).to_i, lonlat: 'POINT(-73.9 40.7)')
  end

  before do
    create(:shared_link, user: user, resource_type: :track, resource_id: route.id)
    { route => [5, 15], batch => [0, 20] }.each do |track, minutes|
      minutes.each do |minute|
        create(:point, user: user, tracker_id: 'phone', track: track, timestamp: (start + minute.minutes).to_i,
                       lonlat: "POINT(#{-74.0060 - (minute * 0.00005)} 40.7128)")
      end
    end
  end

  after { delete_user_data(user) }

  # A chunk building a new track writes track revisions before point revisions;
  # extending a shared track over a batch track must take them in the same order.
  it 'extends a kept track in the track-builder lock order' do
    without_per_user_triggers do
      builder_holds_track_revision = Queue.new
      detector_pid = Queue.new
      builder = in_thread do |connection|
        connection.transaction do
          create(:track, user: user, tracker_id: 'watch', start_at: start + 2.hours, end_at: start + 2.hours + 60)
          builder_holds_track_revision << true
          wait_for_lock_wait(detector_pid.pop)
          connection.execute("UPDATE points SET track_id = track_id WHERE id = #{untracked.id}")
        end
        :committed
      rescue ActiveRecord::Deadlocked
        :deadlocked
      end
      Timeout.timeout(5) { builder_holds_track_revision.pop }
      allow(ExceptionReporter).to receive(:call)

      detector = in_thread do |connection|
        detector_pid << backend_pid(connection)
        described_class.new(user).resolve_cross_chunk_tracks
      end

      expect([builder.value, detector.value]).to eq([:committed, 1])
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Point.where(track_id: batch.id)).to be_empty
      expect([route.reload.start_at, route.end_at]).to eq([start, start + 20.minutes])
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BulkTrackCreator do
  describe '#call' do
    let!(:active_user) { create(:user) }
    let!(:inactive_user) { create(:user, :inactive) }
    let!(:user_without_points) { create(:user) }

    let(:start_at) { 1.day.ago.beginning_of_day }
    let(:end_at) { 1.day.ago.end_of_day }

    before do
      # Create points for active user in the target timeframe
      create(:point, user: active_user, timestamp: start_at.to_i + 1.hour.to_i)
      create(:point, user: active_user, timestamp: start_at.to_i + 2.hours.to_i)

      # Create points for inactive user in the target timeframe
      create(:point, user: inactive_user, timestamp: start_at.to_i + 1.hour.to_i)
    end

    context 'when explicit start_at is provided' do
      it 'schedules tracks creation jobs for active users with points in the timeframe' do
        expect {
          described_class.new(start_at:, end_at:).call
        }.to have_enqueued_job(Tracks::CreateJob).with(active_user.id, start_at:, end_at:, cleaning_strategy: :daily)
      end

      it 'does not schedule jobs for users without tracked points' do
        expect {
          described_class.new(start_at:, end_at:).call
        }.not_to have_enqueued_job(Tracks::CreateJob).with(user_without_points.id, start_at:, end_at:, cleaning_strategy: :daily)
      end

      it 'does not schedule jobs for users without points in the specified timeframe' do
        # Create a user with points outside the timeframe
        user_with_old_points = create(:user)
        create(:point, user: user_with_old_points, timestamp: 2.days.ago.to_i)

        expect {
          described_class.new(start_at:, end_at:).call
        }.not_to have_enqueued_job(Tracks::CreateJob).with(user_with_old_points.id, start_at:, end_at:, cleaning_strategy: :daily)
      end
    end

    context 'when specific user_ids are provided' do
      it 'only processes the specified users' do
        expect {
          described_class.new(start_at:, end_at:, user_ids: [active_user.id]).call
        }.to have_enqueued_job(Tracks::CreateJob).with(active_user.id, start_at:, end_at:, cleaning_strategy: :daily)
      end

      it 'does not process users not in the user_ids list' do
        expect {
          described_class.new(start_at:, end_at:, user_ids: [active_user.id]).call
        }.not_to have_enqueued_job(Tracks::CreateJob).with(inactive_user.id, start_at:, end_at:, cleaning_strategy: :daily)
      end
    end

    context 'with automatic start time determination' do
      let(:user_with_tracks) { create(:user) }
      let(:user_without_tracks) { create(:user) }
      let(:current_time) { Time.current }

      before do
        # Create some historical points and tracks for user_with_tracks
        create(:point, user: user_with_tracks, timestamp: 3.days.ago.to_i)
        create(:point, user: user_with_tracks, timestamp: 2.days.ago.to_i)

        # Create a track ending 1 day ago
        create(:track, user: user_with_tracks, end_at: 1.day.ago)

        # Create newer points after the last track
        create(:point, user: user_with_tracks, timestamp: 12.hours.ago.to_i)
        create(:point, user: user_with_tracks, timestamp: 6.hours.ago.to_i)

        # Create points for user without tracks
        create(:point, user: user_without_tracks, timestamp: 2.days.ago.to_i)
        create(:point, user: user_without_tracks, timestamp: 1.day.ago.to_i)
      end

      it 'starts from the end of the last track for users with existing tracks' do
        track_end_time = user_with_tracks.tracks.order(end_at: :desc).first.end_at

        expect {
          described_class.new(end_at: current_time, user_ids: [user_with_tracks.id]).call
        }.to have_enqueued_job(Tracks::CreateJob).with(
          user_with_tracks.id,
          start_at: track_end_time,
          end_at: current_time.to_datetime,
          cleaning_strategy: :daily
        )
      end

      it 'starts from the oldest point for users without tracks' do
        oldest_point_time = Time.zone.at(user_without_tracks.tracked_points.order(:timestamp).first.timestamp)

        expect {
          described_class.new(end_at: current_time, user_ids: [user_without_tracks.id]).call
        }.to have_enqueued_job(Tracks::CreateJob).with(
          user_without_tracks.id,
          start_at: oldest_point_time,
          end_at: current_time.to_datetime,
          cleaning_strategy: :daily
        )
      end

      it 'falls back to 1 day ago for users with no points' do
        expect {
          described_class.new(end_at: current_time, user_ids: [user_without_points.id]).call
        }.not_to have_enqueued_job(Tracks::CreateJob).with(
          user_without_points.id,
          start_at: anything,
          end_at: anything,
          cleaning_strategy: :daily
        )
      end
    end

    context 'with default parameters' do
      let(:user_with_recent_points) { create(:user) }

      before do
        # Create points within yesterday's timeframe
        create(:point, user: user_with_recent_points, timestamp: 1.day.ago.beginning_of_day.to_i + 2.hours.to_i)
        create(:point, user: user_with_recent_points, timestamp: 1.day.ago.beginning_of_day.to_i + 6.hours.to_i)
      end

      it 'uses automatic start time determination with yesterday as end_at' do
        oldest_point_time = Time.zone.at(user_with_recent_points.tracked_points.order(:timestamp).first.timestamp)

        expect {
          described_class.new(user_ids: [user_with_recent_points.id]).call
        }.to have_enqueued_job(Tracks::CreateJob).with(
          user_with_recent_points.id,
          start_at: oldest_point_time,
          end_at: 1.day.ago.end_of_day.to_datetime,
          cleaning_strategy: :daily
        )
      end
    end
  end

  describe '#start_time' do
    let(:user) { create(:user) }
    let(:service) { described_class.new }

    context 'when user has tracks' do
      let!(:old_track) { create(:track, user: user, end_at: 3.days.ago) }
      let!(:recent_track) { create(:track, user: user, end_at: 1.day.ago) }

      it 'returns the end time of the most recent track' do
        result = service.send(:start_time, user)
        expect(result).to eq(recent_track.end_at)
      end
    end

    context 'when user has no tracks but has points' do
      let!(:old_point) { create(:point, user: user, timestamp: 5.days.ago.to_i) }
      let!(:recent_point) { create(:point, user: user, timestamp: 2.days.ago.to_i) }

      it 'returns the timestamp of the oldest point' do
        result = service.send(:start_time, user)
        expect(result).to eq(Time.zone.at(old_point.timestamp))
      end
    end

    context 'when user has no tracks and no points' do
      it 'returns 1 day ago beginning of day' do
        result = service.send(:start_time, user)
        expect(result).to eq(1.day.ago.beginning_of_day)
      end
    end
  end
end

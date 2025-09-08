# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::DailyGenerationJob, type: :job do
  describe '#perform' do
    let!(:active_user) { create(:user, settings: { 'minutes_between_routes' => 60, 'meters_between_routes' => 500 }) }
    let!(:trial_user) { create(:user, :trial) }
    let!(:inactive_user) { create(:user, :inactive) }

    let!(:active_user_old_track) do
      create(:track, user: active_user, start_at: 2.days.ago, end_at: 2.days.ago + 1.hour)
    end
    let!(:active_user_new_points) do
      create_list(:point, 3, user: active_user, timestamp: 1.hour.ago.to_i)
    end

    let!(:trial_user_old_track) do
      create(:track, user: trial_user, start_at: 3.days.ago, end_at: 3.days.ago + 1.hour)
    end
    let!(:trial_user_new_points) do
      create_list(:point, 2, user: trial_user, timestamp: 30.minutes.ago.to_i)
    end

    before do
      # Update points_count for users to reflect actual points
      active_user.update!(points_count: active_user.points.count)
      trial_user.update!(points_count: trial_user.points.count)

      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it 'processes all active and trial users' do
      expect { described_class.perform_now }.to \
        have_enqueued_job(Tracks::ParallelGeneratorJob).twice
    end

    it 'does not process inactive users' do
      # Clear points and tracks to make destruction possible
      Point.destroy_all
      Track.destroy_all

      # Remove active and trial users to isolate test
      active_user.destroy
      trial_user.destroy

      expect do
        described_class.perform_now
      end.not_to have_enqueued_job(Tracks::ParallelGeneratorJob)
    end

    it 'enqueues correct number of parallel generation jobs for users with new points' do
      described_class.perform_now

      enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
        job[:job] == Tracks::ParallelGeneratorJob
      end

      expect(enqueued_jobs.count).to eq(2)
    end

    it 'enqueues parallel generation job for active user with correct parameters' do
      described_class.perform_now

      enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
        job[:job] == Tracks::ParallelGeneratorJob
      end

      active_user_job = enqueued_jobs.find { |job| job[:args].first == active_user.id }
      expect(active_user_job).to be_present
    end

    it 'uses correct start_at timestamp for active user' do
      described_class.perform_now

      enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
        job[:job] == Tracks::ParallelGeneratorJob
      end

      active_user_job = enqueued_jobs.find { |job| job[:args].first == active_user.id }
      job_kwargs = active_user_job[:args].last

      expect(job_kwargs['start_at']).to eq(active_user_old_track.end_at.to_i)
    end

    it 'uses daily mode for parallel generation jobs' do
      described_class.perform_now

      enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
        job[:job] == Tracks::ParallelGeneratorJob
      end

      active_user_job = enqueued_jobs.find { |job| job[:args].first == active_user.id }
      job_kwargs = active_user_job[:args].last

      expect(job_kwargs['mode']).to eq('daily')
    end

    it 'enqueues parallel generation job for trial user' do
      described_class.perform_now

      enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
        job[:job] == Tracks::ParallelGeneratorJob
      end

      trial_user_job = enqueued_jobs.find { |job| job[:args].first == trial_user.id }
      expect(trial_user_job).to be_present
    end

    it 'does not enqueue jobs for users without new points' do
      Point.destroy_all

      expect { described_class.perform_now }.not_to \
        have_enqueued_job(Tracks::ParallelGeneratorJob)
    end

    it 'enqueues parallel generation job for users with no existing tracks' do
      # Create user with no tracks but with points spread over time
      user_no_tracks = create(:user, points_count: 5)
      # Create points with different timestamps so there are "new" points since the first one
      create(:point, user: user_no_tracks, timestamp: 2.hours.ago.to_i)
      create_list(:point, 4, user: user_no_tracks, timestamp: 1.hour.ago.to_i)

      described_class.perform_now

      enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
        job[:job] == Tracks::ParallelGeneratorJob && job[:args].first == user_no_tracks.id
      end

      expect(enqueued_jobs.count).to eq(1)
    end

    it 'uses first point timestamp as start_at for users with no tracks' do
      # Create user with no tracks but with points spread over time
      user_no_tracks = create(:user, points_count: 5)
      # Create points with different timestamps so there are "new" points since the first one
      create(:point, user: user_no_tracks, timestamp: 2.hours.ago.to_i)
      create_list(:point, 4, user: user_no_tracks, timestamp: 1.hour.ago.to_i)

      described_class.perform_now

      enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
        job[:job] == Tracks::ParallelGeneratorJob && job[:args].first == user_no_tracks.id
      end

      # For users with no tracks, should start from first point timestamp
      job_kwargs = enqueued_jobs.first[:args].last
      expect(job_kwargs['start_at']).to eq(user_no_tracks.points.minimum(:timestamp))
    end

    it 'does not raise errors when processing fails' do
      # Ensure users have points so they're not skipped
      active_user.update!(points_count: 5)
      trial_user.update!(points_count: 3)

      allow_any_instance_of(User).to receive(:tracks).and_raise(StandardError, 'Database error')
      allow(ExceptionReporter).to receive(:call)

      expect { described_class.perform_now }.not_to raise_error
    end

    it 'reports exceptions when processing fails' do
      # Ensure users have points so they're not skipped
      active_user.update!(points_count: 5)
      trial_user.update!(points_count: 3)

      allow_any_instance_of(User).to receive(:tracks).and_raise(StandardError, 'Database error')
      allow(ExceptionReporter).to receive(:call)

      described_class.perform_now

      expect(ExceptionReporter).to have_received(:call).at_least(:once)
    end

    context 'when user has no points' do
      let!(:empty_user) { create(:user) }

      it 'skips users with no points' do
        described_class.perform_now

        enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
          job[:job] == Tracks::ParallelGeneratorJob && job[:args][0] == empty_user.id
        end

        expect(enqueued_jobs).to be_empty
      end
    end

    context 'when user has tracks but no new points' do
      let!(:user_with_current_tracks) { create(:user) }
      let!(:recent_points) { create_list(:point, 2, user: user_with_current_tracks, timestamp: 1.hour.ago.to_i) }
      let!(:recent_track) do
        create(:track, user: user_with_current_tracks, start_at: 1.hour.ago, end_at: 30.minutes.ago)
      end

      it 'skips users without new points since last track' do
        described_class.perform_now

        enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
          job[:job] == Tracks::ParallelGeneratorJob && job[:args][0] == user_with_current_tracks.id
        end

        expect(enqueued_jobs).to be_empty
      end
    end
  end
end

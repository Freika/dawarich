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
      active_user.update!(points_count: active_user.points.count)
      trial_user.update!(points_count: trial_user.points.count)

      allow(User).to receive(:active_or_trial)
        .and_return(User.where(id: [active_user.id, trial_user.id]))

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
      expect { described_class.perform_now }.to \
        have_enqueued_job(Tracks::ParallelGeneratorJob).exactly(2).times
    end

    it 'enqueues parallel generation job for active user with correct parameters' do
      expect { described_class.perform_now }.to \
        have_enqueued_job(Tracks::ParallelGeneratorJob).with(
          active_user.id,
          hash_including(mode: 'daily')
        )
    end

    it 'enqueues parallel generation job for trial user' do
      expect { described_class.perform_now }.to \
        have_enqueued_job(Tracks::ParallelGeneratorJob).with(
          trial_user.id,
          hash_including(mode: 'daily')
        )
    end

    it 'does not enqueue jobs for users without new points' do
      Point.destroy_all

      expect { described_class.perform_now }.not_to \
        have_enqueued_job(Tracks::ParallelGeneratorJob)
    end

    context 'when processing fails' do
      before do
        allow_any_instance_of(User).to receive(:tracks).and_raise(StandardError, 'Database error')
        allow(ExceptionReporter).to receive(:call)

        active_user.update!(points_count: 5)
        trial_user.update!(points_count: 3)
      end
      it 'does not raise errors when processing fails' do
        expect { described_class.perform_now }.not_to raise_error
      end

      it 'reports exceptions when processing fails' do
        described_class.perform_now

        expect(ExceptionReporter).to have_received(:call).at_least(:once)
      end
    end

    context 'when user has no points' do
      let!(:empty_user) { create(:user) }

      it 'skips users with no points' do
        expect { described_class.perform_now }.not_to \
          have_enqueued_job(Tracks::ParallelGeneratorJob).with(empty_user.id, any_args)
      end
    end

    context 'when a large-history user has no tracks' do
      let!(:wiped_user) { create(:user) }
      let!(:wiped_user_points) do
        [
          create(:point, user: wiped_user, timestamp: 200.days.ago.to_i),
          create(:point, user: wiped_user, timestamp: 1.hour.ago.to_i)
        ]
      end

      before do
        wiped_user.update!(points_count: described_class::BOOTSTRAP_POINTS_LIMIT + 1)
        allow(User).to receive(:active_or_trial)
          .and_return(User.where(id: [wiped_user.id]))
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        Sidekiq.redis { |redis| redis.del(Tracks::ThrottledBackfillJob.redis_key(wiped_user.id)) }
      end

      it 'does not enqueue a full-history rebuild through the daily path' do
        expect { described_class.perform_now }.not_to \
          have_enqueued_job(Tracks::ParallelGeneratorJob)
      end

      it 'hands the user off to the throttled backfill walker' do
        expect { described_class.perform_now }.to \
          have_enqueued_job(Tracks::ThrottledBackfillJob).with(wiped_user.id, nil)
      end

      it 'does not stack a second walker on the next daily run' do
        described_class.perform_now

        expect { described_class.perform_now }.not_to \
          have_enqueued_job(Tracks::ThrottledBackfillJob).twice
      end

      context 'when self-hosted' do
        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        end

        it 'rebuilds directly without throttling' do
          expect { described_class.perform_now }.to \
            have_enqueued_job(Tracks::ParallelGeneratorJob).with(
              wiped_user.id,
              hash_including(mode: 'daily')
            )
        end

        it 'does not schedule the throttled walker' do
          expect { described_class.perform_now }.not_to \
            have_enqueued_job(Tracks::ThrottledBackfillJob)
        end
      end
    end

    context 'when a small-history user has no tracks' do
      let!(:new_user) { create(:user) }
      let!(:new_user_points) do
        create_list(:point, 3, user: new_user, timestamp: 2.hours.ago.to_i)
      end

      before do
        new_user.update!(points_count: new_user.points.count)
        allow(User).to receive(:active_or_trial)
          .and_return(User.where(id: [new_user.id]))
      end

      it 'still bootstraps track generation' do
        expect { described_class.perform_now }.to \
          have_enqueued_job(Tracks::ParallelGeneratorJob).with(
            new_user.id,
            hash_including(mode: 'daily')
          )
      end
    end

    context 'when user has tracks but no new points' do
      let!(:user_with_current_tracks) { create(:user) }
      let!(:recent_points) { create_list(:point, 2, user: user_with_current_tracks, timestamp: 1.hour.ago.to_i) }
      let!(:recent_track) do
        create(:track, user: user_with_current_tracks, start_at: 1.hour.ago, end_at: 30.minutes.ago)
      end

      before do
        user_with_current_tracks.update!(points_count: user_with_current_tracks.points.count)
      end

      it 'skips users without new points since last track' do
        expect { described_class.perform_now }.not_to \
          have_enqueued_job(Tracks::ParallelGeneratorJob).with(user_with_current_tracks.id, any_args)
      end
    end
  end
end

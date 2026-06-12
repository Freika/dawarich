# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::RealtimeGenerationJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user, settings: { 'minutes_between_routes' => 30, 'meters_between_routes' => 500 }) }

    before do
      allow(Tracks::RealtimeDebouncer).to receive(:new).and_return(
        instance_double(Tracks::RealtimeDebouncer, clear: true)
      )
    end

    context 'when user exists and is active' do
      it 'clears the debounce key' do
        debouncer = instance_double(Tracks::RealtimeDebouncer, clear: true)
        allow(Tracks::RealtimeDebouncer).to receive(:new).with(user.id).and_return(debouncer)

        described_class.perform_now(user.id)

        expect(debouncer).to have_received(:clear)
      end

      it 'calls the incremental generator' do
        generator = instance_double(Tracks::IncrementalGenerator, call: true)
        allow(Tracks::IncrementalGenerator).to receive(:new).with(user).and_return(generator)

        described_class.perform_now(user.id)

        expect(generator).to have_received(:call)
      end
    end

    context 'when user is in trial status' do
      let(:trial_user) { create(:user, :trial) }

      it 'processes the user' do
        generator = instance_double(Tracks::IncrementalGenerator, call: true)
        allow(Tracks::IncrementalGenerator).to receive(:new).with(trial_user).and_return(generator)

        described_class.perform_now(trial_user.id)

        expect(generator).to have_received(:call)
      end
    end

    context 'when user is inactive' do
      let(:inactive_user) do
        user = create(:user)
        user.update!(status: :inactive, active_until: 1.day.ago)
        user
      end

      it 'does not call the incremental generator' do
        allow(Tracks::IncrementalGenerator).to receive(:new)

        described_class.perform_now(inactive_user.id)

        expect(Tracks::IncrementalGenerator).not_to have_received(:new)
      end

      it 'still clears the debounce key' do
        debouncer = instance_double(Tracks::RealtimeDebouncer, clear: true)
        allow(Tracks::RealtimeDebouncer).to receive(:new).with(inactive_user.id).and_return(debouncer)

        described_class.perform_now(inactive_user.id)

        expect(debouncer).to have_received(:clear)
      end
    end

    context 'when user does not exist' do
      it 'does not raise an error' do
        expect { described_class.perform_now(-1) }.not_to raise_error
      end

      it 'does not call the incremental generator' do
        allow(Tracks::IncrementalGenerator).to receive(:new)

        described_class.perform_now(-1)

        expect(Tracks::IncrementalGenerator).not_to have_received(:new)
      end

      it 'still clears the debounce key' do
        debouncer = instance_double(Tracks::RealtimeDebouncer, clear: true)
        allow(Tracks::RealtimeDebouncer).to receive(:new).with(-1).and_return(debouncer)

        described_class.perform_now(-1)

        expect(debouncer).to have_received(:clear)
      end
    end

    context 'when an error occurs' do
      before do
        allow(Tracks::IncrementalGenerator).to receive(:new).and_raise(StandardError, 'Test error')
        allow(ExceptionReporter).to receive(:call)
      end

      it 'reports the exception' do
        described_class.perform_now(user.id)

        expect(ExceptionReporter).to have_received(:call).with(
          instance_of(StandardError),
          "Failed real-time track generation for user #{user.id}"
        )
      end

      it 'does not raise the error' do
        expect { described_class.perform_now(user.id) }.not_to raise_error
      end
    end

    context 'when the per-user lock is held by a concurrent job' do
      let(:debouncer) { instance_double(Tracks::RealtimeDebouncer, clear: true, trigger: true) }
      let(:timeout_error) do
        Tracks::PerUserLock::AcquisitionTimeout.new(
          "Tracks::PerUserLock: could not acquire lock for user_id=#{user.id} within 30.0s"
        )
      end

      before do
        allow(Tracks::RealtimeDebouncer).to receive(:new).with(user.id).and_return(debouncer)
        generator = instance_double(Tracks::IncrementalGenerator)
        allow(generator).to receive(:call).and_raise(timeout_error)
        allow(Tracks::IncrementalGenerator).to receive(:new).with(user).and_return(generator)
        allow(ExceptionReporter).to receive(:call)
      end

      it 'does not report the contention to Sentry/GlitchTip' do
        described_class.perform_now(user.id)

        expect(ExceptionReporter).not_to have_received(:call)
      end

      it 'does not raise the error' do
        expect { described_class.perform_now(user.id) }.not_to raise_error
      end

      it 're-arms the debouncer so the points are retried after the holder releases' do
        described_class.perform_now(user.id)

        expect(debouncer).to have_received(:trigger)
      end
    end

    describe 'reverse geocoding enqueueing' do
      def reset_dedup_keys
        Sidekiq.redis { |r| r.keys('geocode:enq:*').each { |k| r.del(k) } }
      end

      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
        allow(DawarichSettings).to receive(:store_geodata?).and_return(true)
        allow(Tracks::IncrementalGenerator).to receive(:new).and_return(
          instance_double(Tracks::IncrementalGenerator, call: true)
        )
        reset_dedup_keys
      end

      it 'enqueues only points created in the last 5 minutes' do
        old_point = create(:point, user: user, reverse_geocoded_at: nil)
        old_point.update_columns(created_at: 10.minutes.ago)
        recent_point = create(:point, user: user, reverse_geocoded_at: nil)
        reset_dedup_keys

        expect { described_class.perform_now(user.id) }
          .to have_enqueued_job(ReverseGeocodingJob).exactly(1).times
          .and have_enqueued_job(ReverseGeocodingJob).with('Point', recent_point.id, force: false)
      end

      it 'does not enqueue already-geocoded points' do
        create(:point, user: user, reverse_geocoded_at: 1.minute.ago)
        reset_dedup_keys

        expect { described_class.perform_now(user.id) }
          .not_to have_enqueued_job(ReverseGeocodingJob)
      end

      it 'does not enqueue when reverse geocoding is disabled' do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
        create(:point, user: user, reverse_geocoded_at: nil)
        reset_dedup_keys

        expect { described_class.perform_now(user.id) }
          .not_to have_enqueued_job(ReverseGeocodingJob)
      end
    end
  end
end

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
  end
end

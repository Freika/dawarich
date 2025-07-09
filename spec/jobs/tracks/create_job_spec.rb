# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::CreateJob, type: :job do
  let(:user) { create(:user) }

  describe '#perform' do
    let(:service_instance) { instance_double(Tracks::CreateFromPoints) }
    let(:notification_service) { instance_double(Notifications::Create) }

    before do
      allow(Tracks::CreateFromPoints).to receive(:new).with(user, start_at: nil, end_at: nil, cleaning_strategy: :replace).and_return(service_instance)
      allow(service_instance).to receive(:call).and_return(3)
      allow(Notifications::Create).to receive(:new).and_return(notification_service)
      allow(notification_service).to receive(:call)
    end

    it 'calls the service and creates a notification' do
      described_class.new.perform(user.id)

      expect(Tracks::CreateFromPoints).to have_received(:new).with(user, start_at: nil, end_at: nil, cleaning_strategy: :replace)
      expect(service_instance).to have_received(:call)
      expect(Notifications::Create).to have_received(:new).with(
        user: user,
        kind: :info,
        title: 'Tracks Generated',
        content: 'Created 3 tracks from your location data. Check your tracks section to view them.'
      )
      expect(notification_service).to have_received(:call)
    end

    context 'with custom parameters' do
      let(:start_at) { 1.day.ago.beginning_of_day.to_i }
      let(:end_at) { 1.day.ago.end_of_day.to_i }
      let(:cleaning_strategy) { :daily }

      before do
        allow(Tracks::CreateFromPoints).to receive(:new).with(user, start_at: start_at, end_at: end_at, cleaning_strategy: cleaning_strategy).and_return(service_instance)
        allow(service_instance).to receive(:call).and_return(2)
        allow(Notifications::Create).to receive(:new).and_return(notification_service)
        allow(notification_service).to receive(:call)
      end

      it 'passes custom parameters to the service' do
        described_class.new.perform(user.id, start_at: start_at, end_at: end_at, cleaning_strategy: cleaning_strategy)

        expect(Tracks::CreateFromPoints).to have_received(:new).with(user, start_at: start_at, end_at: end_at, cleaning_strategy: cleaning_strategy)
        expect(service_instance).to have_received(:call)
        expect(Notifications::Create).to have_received(:new).with(
          user: user,
          kind: :info,
          title: 'Tracks Generated',
          content: 'Created 2 tracks from your location data. Check your tracks section to view them.'
        )
        expect(notification_service).to have_received(:call)
      end
    end

    context 'when service raises an error' do
      let(:error_message) { 'Something went wrong' }
      let(:service_instance) { instance_double(Tracks::CreateFromPoints) }
      let(:notification_service) { instance_double(Notifications::Create) }

      before do
        allow(Tracks::CreateFromPoints).to receive(:new).with(user, start_at: nil, end_at: nil, cleaning_strategy: :replace).and_return(service_instance)
        allow(service_instance).to receive(:call).and_raise(StandardError, error_message)
        allow(Notifications::Create).to receive(:new).and_return(notification_service)
        allow(notification_service).to receive(:call)
      end

      it 'creates an error notification' do
        described_class.new.perform(user.id)

        expect(Notifications::Create).to have_received(:new).with(
          user: user,
          kind: :error,
          title: 'Track Generation Failed',
          content: "Failed to generate tracks from your location data: #{error_message}"
        )
        expect(notification_service).to have_received(:call)
      end

      it 'reports the error using ExceptionReporter' do
        allow(ExceptionReporter).to receive(:call)

        described_class.new.perform(user.id)

        expect(ExceptionReporter).to have_received(:call).with(
          kind_of(StandardError),
          'Failed to create tracks for user'
        )
      end
    end

    context 'when user does not exist' do
      it 'handles the error gracefully and creates error notification' do
        allow(User).to receive(:find).with(999).and_raise(ActiveRecord::RecordNotFound)
        allow(ExceptionReporter).to receive(:call)
        allow(Notifications::Create).to receive(:new).and_return(instance_double(Notifications::Create, call: nil))

        # Should not raise an error because it's caught by the rescue block
        expect { described_class.new.perform(999) }.not_to raise_error

        expect(ExceptionReporter).to have_received(:call)
      end
    end
  end

  describe 'queue' do
    it 'is queued on default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end
  end
end

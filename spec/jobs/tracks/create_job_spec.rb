# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::CreateJob, type: :job do
  let(:user) { create(:user) }

  describe '#perform' do
    it 'calls the service and creates a notification' do
      service_instance = instance_double(Tracks::CreateFromPoints)
      allow(Tracks::CreateFromPoints).to receive(:new).with(user).and_return(service_instance)
      allow(service_instance).to receive(:call).and_return(3)

      notification_service = instance_double(Notifications::Create)
      allow(Notifications::Create).to receive(:new).and_return(notification_service)
      allow(notification_service).to receive(:call)

      described_class.new.perform(user.id)

      expect(Tracks::CreateFromPoints).to have_received(:new).with(user)
      expect(service_instance).to have_received(:call)
      expect(Notifications::Create).to have_received(:new).with(
        user: user,
        kind: :info,
        title: 'Tracks Generated',
        content: 'Created 3 tracks from your location data. Check your tracks section to view them.'
      )
      expect(notification_service).to have_received(:call)
    end

    context 'when service raises an error' do
      let(:error_message) { 'Something went wrong' }

      before do
        service_instance = instance_double(Tracks::CreateFromPoints)
        allow(Tracks::CreateFromPoints).to receive(:new).with(user).and_return(service_instance)
        allow(service_instance).to receive(:call).and_raise(StandardError, error_message)
      end

      it 'creates an error notification' do
        notification_service = instance_double(Notifications::Create)
        allow(Notifications::Create).to receive(:new).and_return(notification_service)
        allow(notification_service).to receive(:call)

        described_class.new.perform(user.id)

        expect(Notifications::Create).to have_received(:new).with(
          user: user,
          kind: :error,
          title: 'Track Generation Failed',
          content: "Failed to generate tracks from your location data: #{error_message}"
        )
        expect(notification_service).to have_received(:call)
      end

      it 'logs the error' do
        allow(Rails.logger).to receive(:error)
        allow(Notifications::Create).to receive(:new).and_return(instance_double(Notifications::Create, call: nil))

        described_class.new.perform(user.id)

        expect(Rails.logger).to have_received(:error).with("Failed to create tracks for user #{user.id}: #{error_message}")
      end
    end

    context 'when user does not exist' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect {
          described_class.new.perform(999)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'queue' do
    it 'is queued on default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end
  end
end

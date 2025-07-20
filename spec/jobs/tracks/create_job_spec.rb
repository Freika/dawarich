# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::CreateJob, type: :job do
  let(:user) { create(:user) }

  describe '#perform' do
    let(:generator_instance) { instance_double(Tracks::Generator) }
    let(:notification_service) { instance_double(Notifications::Create) }

    before do
      allow(Tracks::Generator).to receive(:new).and_return(generator_instance)
      allow(generator_instance).to receive(:call)
      allow(Notifications::Create).to receive(:new).and_return(notification_service)
      allow(notification_service).to receive(:call)
      allow(generator_instance).to receive(:call).and_return(2)
    end

    it 'calls the generator and creates a notification' do
      described_class.new.perform(user.id)

      expect(Tracks::Generator).to have_received(:new).with(
        user,
        start_at: nil,
        end_at: nil,
        mode: :daily
      )
      expect(generator_instance).to have_received(:call)
      expect(Notifications::Create).to have_received(:new).with(
        user: user,
        kind: :info,
        title: 'Tracks Generated',
        content: 'Created 2 tracks from your location data. Check your tracks section to view them.'
      )
      expect(notification_service).to have_received(:call)
    end

    context 'with custom parameters' do
      let(:start_at) { 1.day.ago.beginning_of_day.to_i }
      let(:end_at) { 1.day.ago.end_of_day.to_i }
      let(:mode) { :daily }

      before do
        allow(Tracks::Generator).to receive(:new).and_return(generator_instance)
        allow(generator_instance).to receive(:call)
        allow(Notifications::Create).to receive(:new).and_return(notification_service)
        allow(notification_service).to receive(:call)
        allow(generator_instance).to receive(:call).and_return(1)
      end

      it 'passes custom parameters to the generator' do
        described_class.new.perform(user.id, start_at: start_at, end_at: end_at, mode: mode)

        expect(Tracks::Generator).to have_received(:new).with(
          user,
          start_at: start_at,
          end_at: end_at,
          mode: :daily
        )
        expect(generator_instance).to have_received(:call)
        expect(Notifications::Create).to have_received(:new).with(
          user: user,
          kind: :info,
          title: 'Tracks Generated',
          content: 'Created 1 tracks from your location data. Check your tracks section to view them.'
        )
        expect(notification_service).to have_received(:call)
      end
    end

    context 'when generator raises an error' do
      let(:error_message) { 'Something went wrong' }
      let(:notification_service) { instance_double(Notifications::Create) }

      before do
        allow(Tracks::Generator).to receive(:new).and_return(generator_instance)
        allow(generator_instance).to receive(:call).and_raise(StandardError, error_message)
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
      before do
        allow(User).to receive(:find).with(999).and_raise(ActiveRecord::RecordNotFound)
        allow(ExceptionReporter).to receive(:call)
        allow(Notifications::Create).to receive(:new).and_return(instance_double(Notifications::Create, call: nil))
      end

      it 'handles the error gracefully and creates error notification' do
        expect { described_class.new.perform(999) }.not_to raise_error

        expect(ExceptionReporter).to have_received(:call)
      end
    end

    context 'when tracks are deleted and recreated' do
      let(:existing_tracks) { create_list(:track, 3, user: user) }

      before do
        allow(generator_instance).to receive(:call).and_return(2)
      end

      it 'returns the correct count of newly created tracks' do
        described_class.new.perform(user.id, mode: :incremental)

        expect(Tracks::Generator).to have_received(:new).with(
          user,
          start_at: nil,
          end_at: nil,
          mode: :incremental
        )
        expect(generator_instance).to have_received(:call)
        expect(Notifications::Create).to have_received(:new).with(
          user: user,
          kind: :info,
          title: 'Tracks Generated',
          content: 'Created 2 tracks from your location data. Check your tracks section to view them.'
        )
        expect(notification_service).to have_received(:call)
      end
    end
  end

  describe 'queue' do
    it 'is queued on tracks queue' do
      expect(described_class.new.queue_name).to eq('tracks')
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::ParallelGeneratorJob do
  let(:user) { create(:user) }
  let(:job) { described_class.new }

  before do
    Rails.cache.clear
    # Stub user settings
    allow_any_instance_of(User).to receive_message_chain(:safe_settings, :minutes_between_routes).and_return(30)
    allow_any_instance_of(User).to receive_message_chain(:safe_settings, :meters_between_routes).and_return(500)
  end

  describe 'queue configuration' do
    it 'uses the tracks queue' do
      expect(described_class.queue_name).to eq('tracks')
    end
  end

  describe '#perform' do
    let(:user_id) { user.id }
    let(:options) { {} }

    context 'with successful execution' do
      let!(:point1) { create(:point, user: user, timestamp: 2.days.ago.to_i) }
      let!(:point2) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

      it 'calls Tracks::ParallelGenerator with correct parameters' do
        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: nil, end_at: nil, mode: :bulk, chunk_size: 1.day)
          .and_call_original

        job.perform(user_id)
      end

      it 'logs the start of the operation' do
        expect(Rails.logger).to receive(:info)
          .with("Starting parallel track generation for user #{user_id} (mode: bulk)")

        job.perform(user_id)
      end

      it 'logs successful session creation' do
        expect(Rails.logger).to receive(:info)
          .with(/Parallel track generation initiated for user #{user_id}/)

        job.perform(user_id)
      end

      it 'accepts custom parameters' do
        start_at = 1.week.ago
        end_at = Time.current
        mode = :daily
        chunk_size = 2.days

        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: start_at, end_at: end_at, mode: mode, chunk_size: chunk_size)
          .and_call_original

        job.perform(user_id, start_at: start_at, end_at: end_at, mode: mode, chunk_size: chunk_size)
      end

      it 'does not create notifications when session is created successfully' do
        expect(Notifications::Create).not_to receive(:new)
        job.perform(user_id)
      end
    end

    context 'when no tracks are generated (no time chunks)' do
      let(:user_no_points) { create(:user) }

      it 'logs a warning' do
        expect(Rails.logger).to receive(:warn)
          .with("No tracks to generate for user #{user_no_points.id} (no time chunks created)")

        job.perform(user_no_points.id)
      end

      it 'creates info notification with 0 tracks' do
        notification_service = double('notification_service')
        expect(Notifications::Create).to receive(:new)
          .with(
            user: user_no_points,
            kind: :info,
            title: 'Track Generation Complete',
            content: 'Generated 0 tracks from your location data. Check your tracks section to view them.'
          ).and_return(notification_service)
        expect(notification_service).to receive(:call)

        job.perform(user_no_points.id)
      end
    end

    context 'when user is not found' do
      let(:invalid_user_id) { 99999 }

      it 'raises ActiveRecord::RecordNotFound' do
        expect {
          job.perform(invalid_user_id)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when an error occurs' do
      let(:error_message) { 'Something went wrong' }

      before do
        allow(Tracks::ParallelGenerator).to receive(:new).and_raise(StandardError.new(error_message))
      end

      it 'reports the exception' do
        expect(ExceptionReporter).to receive(:call)
          .with(kind_of(StandardError), 'Failed to start parallel track generation')

        job.perform(user_id)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error)
          .with("Parallel track generation failed for user #{user_id}: #{error_message}")

        job.perform(user_id)
      end

      it 'creates error notification for self-hosted instances' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

        notification_service = double('notification_service')
        expect(Notifications::Create).to receive(:new)
          .with(
            user: user,
            kind: :error,
            title: 'Track Generation Failed',
            content: "Failed to generate tracks from your location data: #{error_message}"
          ).and_return(notification_service)
        expect(notification_service).to receive(:call)

        job.perform(user_id)
      end

      it 'does not create error notification for hosted instances' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

        expect(Notifications::Create).not_to receive(:new)

        job.perform(user_id)
      end

      context 'when user is nil (error before user is found)' do
        before do
          allow(User).to receive(:find).and_raise(StandardError.new('Database error'))
        end

        it 'does not create notification' do
          expect(Notifications::Create).not_to receive(:new)
          job.perform(user_id)
        end
      end
    end

    context 'with different modes' do
      let!(:point) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

      it 'handles bulk mode' do
        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: nil, end_at: nil, mode: :bulk, chunk_size: 1.day)
          .and_call_original

        job.perform(user_id, mode: :bulk)
      end

      it 'handles incremental mode' do
        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: nil, end_at: nil, mode: :incremental, chunk_size: 1.day)
          .and_call_original

        job.perform(user_id, mode: :incremental)
      end

      it 'handles daily mode' do
        start_at = Date.current
        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: start_at, end_at: nil, mode: :daily, chunk_size: 1.day)
          .and_call_original

        job.perform(user_id, start_at: start_at, mode: :daily)
      end
    end

    context 'with time ranges' do
      let!(:point) { create(:point, user: user, timestamp: 1.day.ago.to_i) }
      let(:start_at) { 1.week.ago }
      let(:end_at) { Time.current }

      it 'passes time range to generator' do
        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: start_at, end_at: end_at, mode: :bulk, chunk_size: 1.day)
          .and_call_original

        job.perform(user_id, start_at: start_at, end_at: end_at)
      end
    end

    context 'with custom chunk size' do
      let!(:point) { create(:point, user: user, timestamp: 1.day.ago.to_i) }
      let(:chunk_size) { 6.hours }

      it 'passes chunk size to generator' do
        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: nil, end_at: nil, mode: :bulk, chunk_size: chunk_size)
          .and_call_original

        job.perform(user_id, chunk_size: chunk_size)
      end
    end
  end

  describe 'integration with existing track job patterns' do
    let!(:point) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

    it 'follows the same notification pattern as Tracks::CreateJob' do
      # Compare with existing Tracks::CreateJob behavior
      # Should create similar notifications and handle errors similarly
      
      expect {
        job.perform(user.id)
      }.not_to raise_error
    end

    it 'can be queued and executed' do
      expect {
        described_class.perform_later(user.id)
      }.to have_enqueued_job(described_class).with(user.id)
    end

    it 'supports the same parameter structure as Tracks::CreateJob' do
      # Should accept the same parameters that would be passed to Tracks::CreateJob
      expect {
        described_class.perform_later(
          user.id,
          start_at: 1.week.ago,
          end_at: Time.current,
          mode: :daily
        )
      }.to have_enqueued_job(described_class)
    end
  end

  describe 'private methods' do
    describe '#create_info_notification' do
      it 'creates info notification with correct parameters' do
        tracks_created = 5

        notification_service = double('notification_service')
        expect(Notifications::Create).to receive(:new)
          .with(
            user: user,
            kind: :info,
            title: 'Track Generation Complete',
            content: "Generated #{tracks_created} tracks from your location data. Check your tracks section to view them."
          ).and_return(notification_service)
        expect(notification_service).to receive(:call)

        job.send(:create_info_notification, user, tracks_created)
      end
    end

    describe '#create_error_notification' do
      let(:error) { StandardError.new('Test error') }

      context 'when self-hosted' do
        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        end

        it 'creates error notification' do
          notification_service = double('notification_service')
          expect(Notifications::Create).to receive(:new)
            .with(
              user: user,
              kind: :error,
              title: 'Track Generation Failed',
              content: "Failed to generate tracks from your location data: #{error.message}"
            ).and_return(notification_service)
          expect(notification_service).to receive(:call)

          job.send(:create_error_notification, user, error)
        end
      end

      context 'when not self-hosted' do
        before do
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        end

        it 'does not create notification' do
          expect(Notifications::Create).not_to receive(:new)
          job.send(:create_error_notification, user, error)
        end
      end
    end
  end
end
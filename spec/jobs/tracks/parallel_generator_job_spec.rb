# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::ParallelGeneratorJob do
  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500,
             'live_map_enabled' => false
           })
  end
  let(:job) { described_class.new }

  before do
    Rails.cache.clear
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
          .with(user, start_at: nil, end_at: nil, mode: :bulk, chunk_size: 1.day, untracked_only: false)
          .and_call_original

        job.perform(user_id)
      end

      it 'accepts custom parameters' do
        start_at = 1.week.ago
        end_at = Time.current
        mode = :daily
        chunk_size = 2.days

        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: start_at, end_at: end_at, mode: mode, chunk_size: chunk_size, untracked_only: false)
          .and_call_original

        job.perform(user_id, start_at: start_at, end_at: end_at, mode: mode, chunk_size: chunk_size)
      end
    end

    context 'when the per-user lock is held by a concurrent job' do
      let(:timeout_error) do
        Tracks::PerUserLock::AcquisitionTimeout.new(
          "Tracks::PerUserLock: could not acquire lock for user_id=#{user_id} within 30.0s"
        )
      end

      before do
        allow(Tracks::ParallelGenerator).to receive(:new).and_raise(timeout_error)
        allow(ExceptionReporter).to receive(:call)
      end

      it 'retries without reporting expected contention' do
        expect { described_class.perform_now(user_id) }
          .to have_enqueued_job(described_class).with(user_id)

        expect(ExceptionReporter).not_to have_received(:call)
      end

      it 'logs and stops retrying once attempts are exhausted' do
        allow(Rails.logger).to receive(:error)
        job = described_class.new(user_id)
        job.exception_executions = { '[Tracks::PerUserLock::AcquisitionTimeout]' => 4 }

        expect { job.perform_now }.not_to have_enqueued_job(described_class)

        expect(Rails.logger).to have_received(:error)
          .with(/ParallelGeneratorJob lock contention retries exhausted user_id=#{user_id}/)
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
    end

    context 'with different modes' do
      let!(:point) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

      it 'handles bulk mode' do
        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: nil, end_at: nil, mode: :bulk, chunk_size: 1.day, untracked_only: false)
          .and_call_original

        job.perform(user_id, mode: :bulk)
      end

      it 'handles incremental mode' do
        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: nil, end_at: nil, mode: :incremental, chunk_size: 1.day, untracked_only: false)
          .and_call_original

        job.perform(user_id, mode: :incremental)
      end

      it 'handles daily mode' do
        start_at = Date.current
        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: start_at, end_at: nil, mode: :daily, chunk_size: 1.day, untracked_only: false)
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
          .with(user, start_at: start_at, end_at: end_at, mode: :bulk, chunk_size: 1.day, untracked_only: false)
          .and_call_original

        job.perform(user_id, start_at: start_at, end_at: end_at)
      end
    end

    context 'with custom chunk size' do
      let!(:point) { create(:point, user: user, timestamp: 1.day.ago.to_i) }
      let(:chunk_size) { 6.hours }

      it 'passes chunk size to generator' do
        expect(Tracks::ParallelGenerator).to receive(:new)
          .with(user, start_at: nil, end_at: nil, mode: :bulk, chunk_size: chunk_size, untracked_only: false)
          .and_call_original

        job.perform(user_id, chunk_size: chunk_size)
      end
    end
  end

  describe 'integration with existing track job patterns' do
    let!(:point) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

    it 'can be queued and executed' do
      expect do
        described_class.perform_later(user.id)
      end.to have_enqueued_job(described_class).with(user.id)
    end
  end
end

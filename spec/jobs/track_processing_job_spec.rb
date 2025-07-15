require 'rails_helper'

RSpec.describe TrackProcessingJob, type: :job do
  let(:user) { create(:user) }
  let(:job) { described_class.new }

  describe '#perform' do
    context 'with bulk mode' do
      it 'calls TrackService with bulk mode' do
        expect_any_instance_of(TrackService).to receive(:call).and_return(3)
        
        job.perform(user.id, 'bulk', cleanup_tracks: true)
      end

      it 'passes options to TrackService' do
        expect(TrackService).to receive(:new).with(
          user,
          mode: :bulk,
          cleanup_tracks: true
        ).and_call_original
        
        expect_any_instance_of(TrackService).to receive(:call)
        
        job.perform(user.id, 'bulk', cleanup_tracks: true)
      end
    end

    context 'with incremental mode' do
      let!(:point) { create(:point, user: user) }

      it 'calls TrackService with incremental mode' do
        expect_any_instance_of(TrackService).to receive(:call).and_return(1)
        
        job.perform(user.id, 'incremental', point_id: point.id)
      end

      it 'passes point_id to TrackService' do
        expect(TrackService).to receive(:new).with(
          user,
          mode: :incremental,
          point_id: point.id
        ).and_call_original
        
        expect_any_instance_of(TrackService).to receive(:call)
        
        job.perform(user.id, 'incremental', point_id: point.id)
      end
    end

    context 'with incremental mode and old point' do
      let!(:point) { create(:point, user: user, created_at: 2.hours.ago) }

      it 'skips processing for old points' do
        expect(TrackService).not_to receive(:new)
        
        job.perform(user.id, 'incremental', point_id: point.id)
      end

      it 'logs the skip' do
        expect(Rails.logger).to receive(:debug).with(/Skipping track processing for old point/)
        
        job.perform(user.id, 'incremental', point_id: point.id)
      end
    end

    context 'with missing point' do
      it 'logs warning and returns early' do
        expect(Rails.logger).to receive(:warn).with(/Point 999 not found/)
        expect(TrackService).not_to receive(:new)
        
        job.perform(user.id, 'incremental', point_id: 999)
      end
    end

    context 'with missing user' do
      it 'logs error and raises exception' do
        expect(Rails.logger).to receive(:error).with(/User 999 not found/)
        
        expect { job.perform(999, 'bulk') }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'with processing error' do
      before do
        allow_any_instance_of(TrackService).to receive(:call).and_raise(StandardError.new('Test error'))
      end

      it 'logs error and calls ExceptionReporter' do
        expect(Rails.logger).to receive(:error).with(/Track processing failed/)
        expect(Rails.logger).to receive(:error) # for backtrace
        expect(ExceptionReporter).to receive(:call).with(
          instance_of(StandardError),
          'Track processing failed',
          hash_including(user_id: user.id, mode: 'bulk')
        )
        
        expect { job.perform(user.id, 'bulk') }.to raise_error(StandardError)
      end
    end

    context 'with custom thresholds' do
      it 'passes custom thresholds to TrackService' do
        expect(TrackService).to receive(:new).with(
          user,
          mode: :bulk,
          cleanup_tracks: false,
          time_threshold_minutes: 30,
          distance_threshold_meters: 1000
        ).and_call_original
        
        expect_any_instance_of(TrackService).to receive(:call)
        
        job.perform(user.id, 'bulk', time_threshold_minutes: 30, distance_threshold_meters: 1000)
      end
    end
  end

  describe 'job configuration' do
    it 'has correct queue' do
      expect(described_class.queue_name).to eq('tracks')
    end

    it 'has retry configuration' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end

    it 'has unique job configuration' do
      expect(described_class.sidekiq_options['unique_for']).to eq(30.seconds)
    end
  end

  describe 'job uniqueness' do
    it 'uses user_id and mode for uniqueness' do
      unique_args_proc = described_class.sidekiq_options['unique_args']
      result = unique_args_proc.call([user.id, 'bulk', { cleanup_tracks: true }])
      
      expect(result).to eq([user.id, 'bulk'])
    end
  end

  describe 'integration with job queue' do
    it 'can be enqueued' do
      expect { described_class.perform_later(user.id, 'bulk') }.to change(ActiveJob::Base.queue_adapter.enqueued_jobs, :size).by(1)
    end

    it 'can be performed now' do
      expect_any_instance_of(TrackService).to receive(:call).and_return(0)
      
      described_class.perform_now(user.id, 'incremental')
    end
  end
end
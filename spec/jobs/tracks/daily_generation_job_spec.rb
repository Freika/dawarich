# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::DailyGenerationJob, type: :job do
  let(:job) { described_class.new }

  before do
    # Clear any existing jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    # Mock the incremental processing callback to avoid interference
    allow_any_instance_of(Point).to receive(:trigger_incremental_track_generation)
  end

  describe 'queue configuration' do
    it 'uses the tracks queue' do
      expect(described_class.queue_name).to eq('tracks')
    end
  end

  describe '#perform' do
    let(:user1) { create(:user) }
    let(:user2) { create(:user) }
    let(:user3) { create(:user) }

    context 'with users having recent activity' do
      before do
        # User1 - has points created yesterday (should be processed)
        create(:point, user: user1, created_at: 1.day.ago, timestamp: 1.day.ago.to_i)

        # User2 - has points created 1.5 days ago (should be processed)
        create(:point, user: user2, created_at: 1.5.days.ago, timestamp: 1.5.days.ago.to_i)

        # User3 - has points created 3 days ago (should NOT be processed)
        create(:point, user: user3, created_at: 3.days.ago, timestamp: 3.days.ago.to_i)
      end

      it 'enqueues parallel generation jobs for users with recent activity' do
        expect {
          job.perform
        }.to have_enqueued_job(Tracks::ParallelGeneratorJob).twice
      end

      it 'enqueues jobs with correct mode and chunk size' do
        job.perform

        enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
        parallel_jobs = enqueued_jobs.select { |job| job['job_class'] == 'Tracks::ParallelGeneratorJob' }

        expect(parallel_jobs.size).to eq(2)

        parallel_jobs.each do |enqueued_job|
          args = enqueued_job['arguments']
          user_id = args[0]
          options = args[1]

          expect([user1.id, user2.id]).to include(user_id)
          expect(options['mode']['value']).to eq('daily')  # ActiveJob serializes symbols
          expect(options['chunk_size']['value']).to eq(6.hours.to_i)  # ActiveJob serializes durations
          expect(options['start_at']).to be_present
          expect(options['end_at']).to be_present
        end
      end

      it 'does not enqueue jobs for users without recent activity' do
        job.perform

        enqueued_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
        parallel_jobs = enqueued_jobs.select { |job| job['job_class'] == 'Tracks::ParallelGeneratorJob' }
        user_ids = parallel_jobs.map { |job| job['arguments'][0] }

        expect(user_ids).to contain_exactly(user1.id, user2.id)
        expect(user_ids).not_to include(user3.id)
      end

      it 'logs the process with counts' do
        allow(Rails.logger).to receive(:info)

        expect(Rails.logger).to receive(:info).with('Starting daily track generation for users with recent activity')
        expect(Rails.logger).to receive(:info).with('Completed daily track generation: 2 users processed, 0 users failed')

        job.perform
      end
    end

    context 'with no users having recent activity' do
      before do
        # All users have old points (older than 2 days)
        create(:point, user: user1, created_at: 3.days.ago, timestamp: 3.days.ago.to_i)
      end

      it 'does not enqueue any parallel generation jobs' do
        expect { job.perform }.not_to have_enqueued_job(Tracks::ParallelGeneratorJob)
      end

      it 'still logs start and completion with zero counts' do
        allow(Rails.logger).to receive(:info)

        expect(Rails.logger).to receive(:info).with('Starting daily track generation for users with recent activity')
        expect(Rails.logger).to receive(:info).with('Completed daily track generation: 0 users processed, 0 users failed')

        job.perform
      end
    end

    context 'when user processing fails' do
      before do
        create(:point, user: user1, created_at: 1.day.ago, timestamp: 1.day.ago.to_i)

        # Mock Tracks::ParallelGeneratorJob to raise an error
        allow(Tracks::ParallelGeneratorJob).to receive(:perform_later).and_raise(StandardError.new("Job failed"))
        allow(Rails.logger).to receive(:info)
      end

      it 'logs the error and continues processing' do
        allow(Rails.logger).to receive(:info)
        
        expect(Rails.logger).to receive(:error).with("Failed to enqueue daily track generation for user #{user1.id}: Job failed")
        expect(ExceptionReporter).to receive(:call).with(instance_of(StandardError), "Daily track generation failed for user #{user1.id}")
        expect(Rails.logger).to receive(:info).with('Completed daily track generation: 0 users processed, 1 users failed')

        expect { job.perform }.not_to raise_error
      end
    end

    context 'with users having no points' do
      it 'does not process users without any points' do
        # user1, user2, user3 exist but have no points

        expect { job.perform }.not_to have_enqueued_job(Tracks::ParallelGeneratorJob)
      end
    end
  end
end

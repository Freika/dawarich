# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::RealtimeDebouncer do
  let(:user) { create(:user) }
  let(:debouncer) { described_class.new(user.id) }
  let(:redis_key) { "visit_realtime:user:#{user.id}" }

  before do
    Sidekiq.redis { |r| r.del(redis_key) }
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
  end

  describe '#trigger' do
    context 'when reverse geocoding is disabled' do
      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
      end

      it 'does not enqueue VisitSuggestingJob' do
        expect { debouncer.trigger }.not_to have_enqueued_job(VisitSuggestingJob)
      end

      it 'does not set a Redis key' do
        debouncer.trigger

        Sidekiq.redis do |redis|
          expect(redis.exists(redis_key)).to eq(0)
        end
      end
    end

    context 'when called for the first time' do
      it 'sets the Redis key' do
        debouncer.trigger

        Sidekiq.redis do |redis|
          expect(redis.exists(redis_key)).to eq(1)
        end
      end

      it 'schedules a VisitSuggestingJob for this user' do
        expect { debouncer.trigger }.to have_enqueued_job(VisitSuggestingJob)
          .with(hash_including(user_id: user.id))
      end

      it 'schedules the job with a delay' do
        debouncer.trigger

        job = ActiveJob::Base.queue_adapter.enqueued_jobs.find do |j|
          j['job_class'] == 'VisitSuggestingJob'
        end

        expect(job['scheduled_at']).to be_present
      end

      it 'covers a recent lookback window' do
        debouncer.trigger

        job = ActiveJob::Base.queue_adapter.enqueued_jobs.find do |j|
          j['job_class'] == 'VisitSuggestingJob'
        end
        args = job['arguments'].first

        start_at = Time.zone.parse(args['start_at'])
        end_at = Time.zone.parse(args['end_at'])

        expect(end_at - start_at).to be_within(1.minute).of(described_class::LOOKBACK_WINDOW)
      end
    end

    context 'when called multiple times in quick succession' do
      it 'only schedules one job' do
        3.times { debouncer.trigger }

        jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |j|
          j['job_class'] == 'VisitSuggestingJob'
        end

        expect(jobs.size).to eq(1)
      end

      it 'extends the Redis key TTL' do
        debouncer.trigger

        Sidekiq.redis do |redis|
          initial_ttl = redis.ttl(redis_key)
          sleep 0.1
          debouncer.trigger
          new_ttl = redis.ttl(redis_key)

          expect(new_ttl).to be >= initial_ttl - 1
        end
      end
    end

    context 'with different users' do
      let(:other_user) { create(:user) }
      let(:other_debouncer) { described_class.new(other_user.id) }

      it 'schedules separate jobs for each user' do
        debouncer.trigger
        other_debouncer.trigger

        jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |j|
          j['job_class'] == 'VisitSuggestingJob'
        end

        expect(jobs.size).to eq(2)

        user_ids = jobs.map { |j| j['arguments'].first['user_id'] }
        expect(user_ids).to contain_exactly(user.id, other_user.id)
      end
    end
  end

  describe '#clear' do
    it 'removes the Redis key' do
      debouncer.trigger

      Sidekiq.redis do |redis|
        expect(redis.exists(redis_key)).to eq(1)
      end

      debouncer.clear

      Sidekiq.redis do |redis|
        expect(redis.exists(redis_key)).to eq(0)
      end
    end
  end
end

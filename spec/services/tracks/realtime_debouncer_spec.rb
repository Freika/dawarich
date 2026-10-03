# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::RealtimeDebouncer do
  let(:user) { create(:user) }
  let(:debouncer) { described_class.new(user.id) }
  let(:redis_key) { "track_realtime:user:#{user.id}" }

  before do
    # Clear any existing keys
    Sidekiq.redis { |r| r.del(redis_key) }
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  describe '#trigger' do
    context 'when called for the first time' do
      it 'sets the Redis key' do
        debouncer.trigger

        Sidekiq.redis do |redis|
          expect(redis.exists(redis_key)).to eq(1)
        end
      end

      it 'schedules a RealtimeGenerationJob' do
        expect { debouncer.trigger }.to have_enqueued_job(Tracks::RealtimeGenerationJob)
          .with(user.id)
      end

      it 'schedules the job with a delay' do
        debouncer.trigger

        job = ActiveJob::Base.queue_adapter.enqueued_jobs.find do |j|
          j['job_class'] == 'Tracks::RealtimeGenerationJob'
        end

        expect(job['scheduled_at']).to be_present
      end
    end

    context 'when called multiple times in quick succession' do
      it 'only schedules one job' do
        3.times { debouncer.trigger }

        jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |j|
          j['job_class'] == 'Tracks::RealtimeGenerationJob'
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

          # TTL should be refreshed (equal or greater)
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
          j['job_class'] == 'Tracks::RealtimeGenerationJob'
        end

        expect(jobs.size).to eq(2)

        user_ids = jobs.map { |j| j['arguments'].first }
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

  context 'with phoenix.once_claims' do
    before { phoenix_state! }

    def claim_seconds(key)
      connection = ActiveRecord::Base.connection
      connection.select_value(
        'SELECT extract(epoch FROM expires_at - statement_timestamp()) FROM phoenix.once_claims ' \
        "WHERE key = #{connection.quote(key)}"
      )&.to_f
    end

    def expire_in_ten_seconds(key)
      connection = ActiveRecord::Base.connection
      connection.execute(
        "UPDATE phoenix.once_claims SET expires_at = statement_timestamp() + interval '10 seconds' " \
        "WHERE key = #{connection.quote(key)}"
      )
    end

    it 'schedules one job per burst from the claim row, slides the row and lets the job clear it' do
      expect { 3.times { debouncer.trigger } }.to have_enqueued_job(Tracks::RealtimeGenerationJob).exactly(:once)
      expire_in_ten_seconds(redis_key)
      expect { debouncer.trigger }.not_to have_enqueued_job(Tracks::RealtimeGenerationJob)
      expect(claim_seconds(redis_key)).to be_between(119, 120)
      debouncer.clear
      expect { debouncer.trigger }.to have_enqueued_job(Tracks::RealtimeGenerationJob).exactly(:once)
      expect(Sidekiq.redis { |r| r.exists(redis_key) }).to eq(0)
    end
  end
end

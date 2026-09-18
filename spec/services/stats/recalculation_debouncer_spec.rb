# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::RecalculationDebouncer do
  let(:user) { create(:user) }
  let(:debouncer) { described_class.new(user.id) }
  let(:redis_key) { "stats_full_recalculation:user:#{user.id}" }

  before do
    Sidekiq.redis { |redis| redis.del(redis_key) }
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  describe '#trigger' do
    it 'schedules a delayed full recalculation on the first call' do
      expect { debouncer.trigger }
        .to have_enqueued_job(Stats::FullRecalculationJob).with(user.id)
    end

    it 'schedules the job with a delay rather than immediately' do
      debouncer.trigger

      job = ActiveJob::Base.queue_adapter.enqueued_jobs.find do |enqueued|
        enqueued['job_class'] == 'Stats::FullRecalculationJob'
      end

      expect(job['scheduled_at']).to be_present
    end

    it 'collapses a burst of changes into a single scheduled job' do
      expect { 10.times { debouncer.trigger } }
        .to have_enqueued_job(Stats::FullRecalculationJob).with(user.id).exactly(:once)
    end

    it 'schedules again once the window has been cleared' do
      debouncer.trigger
      debouncer.clear

      expect { debouncer.trigger }
        .to have_enqueued_job(Stats::FullRecalculationJob).with(user.id).exactly(:once)
    end
  end

  describe '#clear' do
    it 'removes the debounce key' do
      debouncer.trigger
      debouncer.clear

      Sidekiq.redis { |redis| expect(redis.exists(redis_key)).to eq(0) }
    end
  end
end

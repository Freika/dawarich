# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::ThrottledBackfillJob, type: :job do
  let(:user) { create(:user) }

  before do
    Sidekiq.redis { |redis| redis.del(described_class.redis_key(user.id)) }
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  describe '.schedule' do
    it 'enqueues the walker for a user' do
      expect { described_class.schedule(user) }.to \
        have_enqueued_job(described_class).with(user.id, nil)
    end

    it 'does not enqueue a second walker while one is scheduled' do
      described_class.schedule(user)

      expect { described_class.schedule(user) }.not_to \
        have_enqueued_job(described_class).twice
    end
  end

  describe '#perform' do
    context 'when the user has points below the cursor' do
      let!(:old_point) { create(:point, user: user, timestamp: 100.days.ago.to_i) }
      let!(:newest_point) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

      it 'generates one slice anchored at the newest point, untracked only' do
        described_class.perform_now(user.id, nil)

        expect(Tracks::TimeChunkProcessorJob).to have_been_enqueued.with(
          user.id,
          anything,
          hash_including(
            untracked_only: true,
            end_timestamp: newest_point.timestamp
          )
        )
      end

      it 'keeps the slice fan-out off the tracks queue' do
        described_class.perform_now(user.id, nil)

        expect(Tracks::TimeChunkProcessorJob).to have_been_enqueued.on_queue('low_priority')
        expect(Tracks::TimeChunkProcessorJob).not_to have_been_enqueued.on_queue('tracks')
      end

      it 'slices the walk into day-sized chunks' do
        described_class.perform_now(user.id, nil)

        expect(Tracks::TimeChunkProcessorJob).to have_been_enqueued.with(
          user.id,
          anything,
          hash_including(
            start_timestamp: newest_point.timestamp - 1.day.to_i,
            end_timestamp: newest_point.timestamp
          )
        )
      end

      it 're-enqueues itself with the cursor moved below the slice' do
        described_class.perform_now(user.id, nil)

        expect(described_class).to have_been_enqueued.with(
          user.id,
          newest_point.timestamp - described_class::SLICE.to_i
        )
      end
    end

    context 'when history has a gap below the cursor' do
      let!(:ancient_point) { create(:point, user: user, timestamp: 400.days.ago.to_i) }

      it 'jumps the slice to the newest point below the cursor instead of walking empty windows' do
        described_class.perform_now(user.id, 100.days.ago.to_i)

        expect(Tracks::TimeChunkProcessorJob).to have_been_enqueued.with(
          user.id,
          anything,
          hash_including(end_timestamp: ancient_point.timestamp)
        )
      end
    end

    context 'when no points remain below the cursor' do
      let!(:recent_point) { create(:point, user: user, timestamp: 1.day.ago.to_i) }

      before do
        Sidekiq.redis { |redis| redis.set(described_class.redis_key(user.id), 1) }
      end

      it 'does not enqueue any generation and starts the completion backoff' do
        described_class.perform_now(user.id, 300.days.ago.to_i)

        expect(Tracks::TimeChunkProcessorJob).not_to have_been_enqueued
        expect(described_class).not_to have_been_enqueued

        ttl = Sidekiq.redis { |redis| redis.ttl(described_class.redis_key(user.id)) }
        expect(ttl).to be > described_class::DEDUP_KEY_TTL.to_i
      end

      it 'does not start a new walker during the completion backoff' do
        described_class.perform_now(user.id, 300.days.ago.to_i)

        expect { described_class.schedule(user) }.not_to \
          have_enqueued_job(described_class)
      end
    end

    context 'when the user no longer exists' do
      it 'releases the dedup key and stops' do
        Sidekiq.redis { |redis| redis.set(described_class.redis_key(0), 1) }

        described_class.perform_now(0, nil)

        expect(described_class).not_to have_been_enqueued
        key_exists = Sidekiq.redis { |redis| redis.exists(described_class.redis_key(0)) }
        expect(key_exists).to eq(0)
      end
    end
  end
end

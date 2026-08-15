# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::PerUserLock do
  let(:user_id) { 1410 }
  let(:redis_key) { "tracks:per_user_lock:#{user_id}" }

  before do
    Sidekiq.redis do |r|
      r.del(redis_key)
      r.del("tracks:per_user_lock:#{user_id + 1}")
    end
  end

  describe '.with_user_lock' do
    it 'yields and returns the block value' do
      result = described_class.with_user_lock(user_id) { :yielded }

      expect(result).to eq(:yielded)
    end

    it 'holds the lock for the duration of the block' do
      observed_during_block = nil

      described_class.with_user_lock(user_id) do
        observed_during_block = Sidekiq.redis { |r| r.exists(redis_key) }
      end

      expect(observed_during_block).to eq(1)
    end

    it 'releases the lock after the block completes' do
      described_class.with_user_lock(user_id) { :ok }

      released = Sidekiq.redis { |r| r.exists(redis_key) }
      expect(released).to eq(0)
    end

    it 'releases the lock when the block raises' do
      expect do
        described_class.with_user_lock(user_id) { raise 'boom' }
      end.to raise_error('boom')

      released = Sidekiq.redis { |r| r.exists(redis_key) }
      expect(released).to eq(0)
    end

    it 'sets a TTL on the lock key so a crashed worker cannot orphan it' do
      lock_ttl = nil

      described_class.with_user_lock(user_id) do
        lock_ttl = Sidekiq.redis { |r| r.ttl(redis_key) }
      end

      expect(lock_ttl).to be > 0
    end

    it 'uses a short lease so an orphaned lock frees within about a minute' do
      remaining_ms = nil

      described_class.with_user_lock(user_id) do
        remaining_ms = Sidekiq.redis { |r| r.pttl(redis_key) }
      end

      expect(remaining_ms).to be_between(1, 60_000)
    end

    it 'renews the lock so it survives a block that outlives the initial lease' do
      remaining_ms = nil

      described_class.with_user_lock(user_id, ttl: 2) do
        sleep 2.6
        remaining_ms = Sidekiq.redis { |r| r.pttl(redis_key) }
      end

      expect(remaining_ms).to be > 0
    end

    it 'keeps renewing after a transient redis error instead of giving up' do
      calls = 0
      original_renew = described_class.method(:renew)
      allow(described_class).to receive(:renew) do |*args|
        calls += 1
        raise 'transient redis blip' if calls == 1

        original_renew.call(*args)
      end

      remaining_ms = nil
      described_class.with_user_lock(user_id, ttl: 2) do
        sleep 2.5
        remaining_ms = Sidekiq.redis { |r| r.pttl(redis_key) }
      end

      expect(calls).to be >= 2
      expect(remaining_ms).to be > 0
    end

    it 'stops renew attempts once consecutive redis errors exhaust the lease' do
      calls = 0
      allow(described_class).to receive(:renew) do
        calls += 1
        raise 'redis down'
      end

      described_class.with_user_lock(user_id, ttl: 0.6) { sleep 1.4 }

      expect(calls).to eq(described_class::MAX_RENEW_ERRORS)
    end

    it 'raises AcquisitionTimeout when another holder owns the lock' do
      Sidekiq.redis { |r| r.set(redis_key, 'other-owner', ex: 60) }

      expect do
        described_class.with_user_lock(user_id, timeout: 0.2) { :never_runs }
      end.to raise_error(Tracks::PerUserLock::AcquisitionTimeout, /user_id=#{user_id}/)
    end

    it 'does not delete a lock held by a different owner' do
      Sidekiq.redis { |r| r.set(redis_key, 'other-owner', ex: 60) }

      expect do
        described_class.with_user_lock(user_id, timeout: 0.1) { :never_runs }
      end.to raise_error(Tracks::PerUserLock::AcquisitionTimeout)

      remaining = Sidekiq.redis { |r| r.get(redis_key) }
      expect(remaining).to eq('other-owner')
    end

    it 'serializes concurrent callers per user' do
      first_started = false
      second_started = false
      contention_observed = false

      first = Thread.new do
        described_class.with_user_lock(user_id, timeout: 5) do
          first_started = true
          sleep 0.2
          contention_observed = second_started == false
        end
      end

      Thread.pass until first_started

      second = Thread.new do
        described_class.with_user_lock(user_id, timeout: 5) do
          second_started = true
        end
      end

      [first, second].each(&:join)

      expect(contention_observed).to be(true)
      expect(second_started).to be(true)
    end

    it 'isolates locks per user_id' do
      acquired_other = false

      described_class.with_user_lock(user_id) do
        described_class.with_user_lock(user_id + 1, timeout: 0.5) do
          acquired_other = true
        end
      end

      expect(acquired_other).to be(true)
    end
  end
end

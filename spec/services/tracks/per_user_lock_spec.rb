# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::PerUserLock do
  let(:user_id) { 1410 }
  let(:name) { "tracks:per_user_lock:#{user_id}" }
  let(:connection) { ActiveRecord::Base.connection }

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def lease_rows
    connection.select_rows(
      "SELECT holder, expires_at > statement_timestamp() FROM phoenix.leases WHERE name = #{connection.quote(name)}"
    )
  end

  def expires_at
    connection.select_value("SELECT expires_at FROM phoenix.leases WHERE name = #{connection.quote(name)}")
  end

  def plant(holder, offset)
    connection.execute(
      'INSERT INTO phoenix.leases (name, holder, expires_at) ' \
      "VALUES (#{connection.quote(name)}, #{connection.quote(holder)}, " \
      "statement_timestamp() + interval #{connection.quote(offset)})"
    )
  end

  before { Sidekiq.redis { |r| r.del(name) } }
  after { Sidekiq.redis { |r| r.del(name) } }

  it 'uses the lease name Phoenix uses' do
    source = Rails.root.join('app-phoenix/lib/dawarich/tracks/per_user_lock.ex').read
    expect(source).to include("\"tracks:per_user_lock:\#{user_id}\"")
    expect("#{described_class::NAMESPACE}:#{user_id}").to eq(name)
  end

  context 'with phoenix.leases (Phoenix migrated)' do
    before { phoenix_leases! }

    it 'holds the shared lease for the block, releases it afterwards and writes no Redis key' do
      expect(described_class.with_user_lock(user_id) { lease_rows }).to match([[kind_of(String), true]])
      expect(lease_rows).to be_empty
      expect(Sidekiq.redis { |r| r.exists(name) }).to eq(0)
    end

    it 'releases the lease when the block raises' do
      expect { described_class.with_user_lock(user_id) { raise 'boom' } }.to raise_error('boom')
      expect(lease_rows).to be_empty
    end

    it 'raises AcquisitionTimeout at once while Phoenix holds the lease, and leaves it alone' do
      plant('phoenix-token', '60 seconds')
      ran = false

      expect { described_class.with_user_lock(user_id, timeout: 0) { ran = true } }
        .to raise_error(described_class::AcquisitionTimeout, /user_id=#{user_id}/)
      expect(ran).to be(false)
      expect(lease_rows).to eq([['phoenix-token', true]])
    end

    it 'takes over the lease of a holder that crashed and let it expire' do
      plant('crashed', '-1 second')
      expect(described_class.with_user_lock(user_id, timeout: 0) { lease_rows })
        .to match([[satisfy { |holder| holder != 'crashed' }, true]])
    end

    it 'isolates locks per user' do
      plant('phoenix-token', '60 seconds')
      expect(described_class.with_user_lock(user_id + 1, timeout: 0) { :ran }).to eq(:ran)
    end

    it 'renews the lease while the block outlives a third of its ttl' do
      described_class.with_user_lock(user_id, ttl: 0.3) do
        first = expires_at
        deadline = monotonic + 5
        sleep 0.02 until expires_at > first || monotonic > deadline
        expect(expires_at).to be > first
      end
    end

    it 'gives up renewing after three consecutive errors' do
      calls = 0
      allow(PhoenixLease).to receive(:renew) do
        calls += 1
        raise ActiveRecord::ConnectionNotEstablished
      end

      beat = described_class.start_heartbeat(PhoenixLease, name, 'token', 0.3, user_id)

      expect(beat[:thread].join(5)).not_to be_nil
      expect(calls).to eq(described_class::MAX_RENEW_ERRORS)
    end
  end

  context 'without phoenix.leases (Phoenix never migrated)' do
    before { connection.execute('DROP TABLE IF EXISTS phoenix.leases') }

    it 'holds the Redis key for the block and releases it afterwards' do
      remaining = described_class.with_user_lock(user_id) { Sidekiq.redis { |r| r.pttl(name) } }
      expect(remaining).to be_between(1, 60_000)
      expect(Sidekiq.redis { |r| r.exists(name) }).to eq(0)
    end

    it 'raises AcquisitionTimeout while another holder owns the Redis key, and leaves it alone' do
      Sidekiq.redis { |r| r.set(name, 'other-owner', ex: 60) }
      expect { described_class.with_user_lock(user_id, timeout: 0) { :never } }
        .to raise_error(described_class::AcquisitionTimeout)
      expect(Sidekiq.redis { |r| r.get(name) }).to eq('other-owner')
    end

    it 'renews the Redis key while the block outlives a third of its ttl' do
      described_class.with_user_lock(user_id, ttl: 0.3) do
        previous = Sidekiq.redis { |r| r.pttl(name) }
        deadline = monotonic + 5
        renewed = false
        until renewed || monotonic > deadline
          current = Sidekiq.redis { |r| r.pttl(name) }
          renewed = current > previous
          previous = current
          sleep 0.01
        end
        expect(renewed).to be(true)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Lease heartbeats while every application connection is busy', :non_transactional, threads: 4 do
  let(:pool) { ActiveRecord::Base.connection_pool }
  let(:connection) { ActiveRecord::Base.connection }

  before { PhoenixLeaseRecord.connect! }

  after do
    PhoenixLeaseRecord.remove_connection
    connection.execute(
      "DELETE FROM phoenix.leases WHERE name LIKE 'spec:heartbeat:%' OR name = 'tracks:per_user_lock:76543'"
    )
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def expires_at(name)
    connection.select_value("SELECT expires_at FROM phoenix.leases WHERE name = #{connection.quote(name)}")
  end

  def exhaust
    taken = []
    loop { taken << pool.checkout(0.05) }
  rescue ActiveRecord::ConnectionTimeoutError
    taken
  end

  def renewed_while_exhausted?(name)
    first = expires_at(name)
    taken = exhaust
    deadline = monotonic + 3
    sleep 0.02 until expires_at(name) > first || monotonic > deadline
    expires_at(name) > first
  ensure
    taken&.each { pool.checkin(_1) }
  end

  it 'renews a try-once lease on its own connections' do
    name = "spec:heartbeat:#{SecureRandom.hex(4)}"
    expect(PhoenixLeaseRecord.connection_pool.size).to eq(PhoenixLeaseRecord::POOL_SIZE)
    expect(PhoenixLease.try_hold(name, ttl: 0.6) { renewed_while_exhausted?(name) }).to be(true)
    expect(expires_at(name)).to be_nil
  end

  it "renews the per-user track lock on the lease pool's connections" do
    renewed = Tracks::PerUserLock.with_user_lock(76_543, ttl: 0.6) do
      renewed_while_exhausted?('tracks:per_user_lock:76543')
    end
    expect(renewed).to be(true)
    expect(expires_at('tracks:per_user_lock:76543')).to be_nil
  end
end

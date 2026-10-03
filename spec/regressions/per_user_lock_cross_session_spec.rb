# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tracks::PerUserLock across database sessions', :non_transactional, threads: 4 do
  let(:user_id) { 98_765 }
  let(:name) { "tracks:per_user_lock:#{user_id}" }

  before(:context) { phoenix_leases! }
  after(:context) { ActiveRecord::Base.connection.execute('DROP TABLE IF EXISTS phoenix.leases') }

  def in_session(&block) = Thread.new { ActiveRecord::Base.connection_pool.with_connection(&block) }

  def holders
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM phoenix.leases WHERE name = #{ActiveRecord::Base.connection.quote(name)}"
    ).to_i
  end

  it 'keeps a second session out while the first holds the lease, then lets it in' do
    holding = Concurrent::CountDownLatch.new(1)
    finish = Concurrent::CountDownLatch.new(1)
    first = in_session do
      Tracks::PerUserLock.with_user_lock(user_id) do
        holding.count_down
        finish.wait(10)
      end
    end
    second = -> { in_session { Tracks::PerUserLock.with_user_lock(user_id, timeout: 0) { :second } }.value }

    expect(holding.wait(10)).to be(true)
    expect(holders).to eq(1)
    expect { second.call }.to raise_error(Tracks::PerUserLock::AcquisitionTimeout)

    finish.count_down
    first.join(10)
    expect(holders).to eq(0)
    expect(second.call).to eq(:second)
  ensure
    finish&.count_down
    first&.join(10)
  end
end

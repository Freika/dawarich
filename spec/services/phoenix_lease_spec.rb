# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PhoenixLease do
  let(:name) { "import:#{SecureRandom.uuid}" }
  let(:busy) { Class.new(StandardError) }
  let(:connection) { ActiveRecord::Base.connection }

  def rows
    connection.select_rows(
      "SELECT holder, expires_at > statement_timestamp() FROM phoenix.leases WHERE name = #{connection.quote(name)}"
    )
  end

  def expires_at
    connection.select_value("SELECT expires_at FROM phoenix.leases WHERE name = #{connection.quote(name)}")
  end

  def insert(holder, offset)
    connection.execute(<<~SQL.squish)
      INSERT INTO phoenix.leases (name, holder, expires_at)
      VALUES (#{connection.quote(name)}, #{connection.quote(holder)}, now() + interval #{connection.quote(offset)})
    SQL
  end

  context 'with phoenix.leases migrated' do
    before { phoenix_leases! }

    it 'holds the named lease for the block and releases it afterwards' do
      expect(described_class.hold(name, busy.new) { rows }).to match([[kind_of(String), true]])
      expect(rows).to be_empty
    end

    it 'refuses at once while another holder owns an unexpired lease' do
      insert('phoenix-holder', '1 hour')
      ran = false
      expect { described_class.hold(name, busy.new) { ran = true } }.to raise_error(busy)
      expect(ran).to be(false)
      expect(rows).to eq([['phoenix-holder', true]])
    end

    it 'takes over a lease whose holder let it expire' do
      insert('crashed', '-1 second')
      expect(described_class.hold(name, busy.new) { rows }).to match([[satisfy { |h| h != 'crashed' }, true]])
    end

    it 'releases the lease when the block raises' do
      expect { described_class.hold(name, busy.new) { raise ArgumentError } }.to raise_error(ArgumentError)
      expect(rows).to be_empty
    end

    it 'renews and releases only for the current holder' do
      expect(described_class.acquire(name, 'a', 60)).to be(true)
      expect(described_class.acquire(name, 'b', 60)).to be(false)
      expect(described_class.renew(name, 'b', 60)).to be(false)
      expect(described_class.release(name, 'b')).to be(false)
      expect(described_class.renew(name, 'a', 60)).to be(true)
      expect(described_class.release(name, 'a')).to be(true)
      expect(rows).to be_empty
    end

    it 'try_hold runs the block under the lease and returns its value' do
      expect(described_class.try_hold(name) { rows }).to match([[kind_of(String), true]])
      expect(rows).to be_empty
    end

    it 'try_hold returns false at once while another holder owns the lease' do
      insert('phoenix-holder', '1 hour')
      ran = false
      expect(described_class.try_hold(name) { ran = true }).to be(false)
      expect(ran).to be(false)
      expect(rows).to eq([['phoenix-holder', true]])
    end

    it 'try_hold releases the lease when the block raises' do
      expect { described_class.try_hold(name) { raise ArgumentError } }.to raise_error(ArgumentError)
      expect(rows).to be_empty
    end

    it 'keeps renewing the lease while the block outlives its ttl' do
      described_class.hold(name, busy.new, ttl: 1.5) do
        first = expires_at
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
        sleep 0.05 until expires_at > first || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        expect(expires_at).to be > first
      end
    end
  end

  it 'runs the block without a lease on a database Phoenix never migrated' do
    connection.execute('DROP TABLE IF EXISTS phoenix.leases')
    expect(described_class.hold(name, busy.new) { :ran }).to eq(:ran)
  end

  it 'try_hold falls back to the try-once advisory lock on a database Phoenix never migrated' do
    connection.execute('DROP TABLE IF EXISTS phoenix.leases')
    expect(ActiveRecord::Base).to receive(:with_advisory_lock).with(name, timeout_seconds: 0) { |*, &block| block.call }
    expect(described_class.try_hold(name) { :ran }).to eq(:ran)
  end

  it 'issues the same statements as Dawarich.State.Lease' do
    source = Rails.root.join('app-phoenix/lib/dawarich/state/lease.ex').read
    heredoc = ->(attribute) { source[/@#{attribute} """\n(.*?)\n\s*"""/m, 1].squish }
    expect(described_class::ACQUIRE.squish).to eq(heredoc.call('acquire'))
    expect(described_class::RENEW.squish).to eq(heredoc.call('renew'))
    expect(described_class::RELEASE).to eq(source[/@release "(.*?)"/, 1])
  end
end

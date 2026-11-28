# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::DataLock, :non_transactional, threads: 3 do
  let(:user) { create(:user) }

  def in_thread(&)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&) }
  end

  it 'allows concurrent readers and refuses deletion until they finish' do
    reader_started = Queue.new
    release_reader = Queue.new

    first_reader = in_thread do
      described_class.with_shared(user.id) do
        reader_started << true
        release_reader.pop
      end
    end
    Timeout.timeout(5) { reader_started.pop }

    second_reader_ran = in_thread { described_class.with_shared(user.id) { true } }.value
    expect(second_reader_ran).to be true

    busy = in_thread do
      described_class.with_exclusive(user.id) { :deleted }
    rescue described_class::Busy
      :busy
    end.value
    expect(busy).to eq(:busy)

    release_reader << true
    first_reader.join(5)

    expect(in_thread { described_class.with_exclusive(user.id) { :deleted } }.value).to eq(:deleted)
  ensure
    release_reader << true if first_reader&.alive?
    first_reader&.join(5)
  end

  it 'releases the lock when the block raises' do
    expect { described_class.with_shared(user.id) { raise ArgumentError } }.to raise_error(ArgumentError)

    expect(in_thread { described_class.with_exclusive(user.id) { :deleted } }.value).to eq(:deleted)
  end

  it 'drops the connection when unlocking fails so the lock cannot linger' do
    held = in_thread do |connection|
      allow(connection).to receive(:execute).and_call_original
      allow(connection).to receive(:execute).with(/pg_advisory_unlock_shared/)
                                            .and_raise(ActiveRecord::StatementInvalid, 'unlock failed')

      described_class.with_shared(user.id) { :imported }
    end.value

    expect(held).to eq(:imported)
    expect(lingering_locks_after_teardown).to eq(0)
  end

  def lingering_locks_after_teardown
    sql = <<~SQL.squish
      SELECT count(*) FROM pg_locks
      WHERE locktype = 'advisory' AND objid = #{user.id} AND classid = #{described_class::NAMESPACE >> 32}
        AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
    SQL
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      count = ActiveRecord::Base.connection.select_value(sql)
      return count if count.zero? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  end

  context 'when advisory locks are disabled' do
    before do
      db_config = ActiveRecord::Base.connection_pool.db_config
      allow(db_config).to receive(:configuration_hash)
        .and_return(db_config.configuration_hash.merge(advisory_locks: false))
    end

    it 'runs the block without taking an advisory lock' do
      statements = []
      callback = ->(*, payload) { statements << payload[:sql] }

      result = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        described_class.with_shared(user.id) { described_class.with_exclusive(user.id) { :ran } }
      end

      expect(result).to eq(:ran)
      expect(statements.grep(/pg_\w*advisory/)).to be_empty
    end
  end
end

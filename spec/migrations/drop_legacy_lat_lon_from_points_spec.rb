# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260714090000_drop_legacy_lat_lon_from_points.rb')

RSpec.describe DropLegacyLatLonFromPoints, :non_transactional do
  subject(:migration) { described_class.new }

  before do
    allow(migration).to receive(:sleep)
    allow(migration).to receive(:column_exists?).and_return(true)
    allow(migration).to receive(:execute).and_call_original
  end

  def stub_drop_raising(error_class, times: described_class::DROP_MAX_ATTEMPTS)
    attempts = 0

    allow(migration).to receive(:execute) do |sql|
      next nil unless sql.include?('DROP COLUMN')

      attempts += 1
      raise error_class, 'canceling statement due to lock timeout' if attempts <= times

      nil
    end

    -> { attempts }
  end

  it 'does not abort the migration when the drop never wins the lock race' do
    stub_drop_raising(ActiveRecord::LockWaitTimeout)
    allow(DataMigrations::DropLegacyLatLonJob).to receive(:perform_later)

    expect { migration.send(:drop_legacy_columns) }.not_to raise_error
  end

  it 'hands the drop to a background job once attempts are exhausted' do
    stub_drop_raising(ActiveRecord::LockWaitTimeout)
    allow(DataMigrations::DropLegacyLatLonJob).to receive(:perform_later)

    migration.send(:drop_legacy_columns)

    expect(DataMigrations::DropLegacyLatLonJob).to have_received(:perform_later)
  end

  it 'retries until the lock is acquired instead of failing on the first loss' do
    attempts = stub_drop_raising(ActiveRecord::LockWaitTimeout, times: 2)
    allow(DataMigrations::DropLegacyLatLonJob).to receive(:perform_later)

    migration.send(:drop_legacy_columns)

    expect(attempts.call).to eq(3)
    expect(DataMigrations::DropLegacyLatLonJob).not_to have_received(:perform_later)
  end

  it 'scopes both timeouts to the transaction so pooling cannot separate them' do
    stub_drop_raising(ActiveRecord::LockWaitTimeout, times: 0)

    migration.send(:drop_legacy_columns)

    expect(migration).to have_received(:execute).with('SET LOCAL statement_timeout = 0')
    expect(migration).to have_received(:execute).with("SET LOCAL lock_timeout = '5s'")
  end

  it 'hands off rather than aborting when a statement_timeout cancels the drop' do
    stub_drop_raising(ActiveRecord::QueryCanceled)

    expect { migration.send(:drop_legacy_columns) }.to have_enqueued_job(DataMigrations::DropLegacyLatLonJob)
  end

  it 'does not abort the migration when the job cannot be enqueued' do
    stub_drop_raising(ActiveRecord::LockWaitTimeout)
    allow(DataMigrations::DropLegacyLatLonJob).to receive(:perform_later).and_raise(
      RedisClient::CannotConnectError, 'connection refused'
    )

    expect { migration.send(:drop_legacy_columns) }.not_to raise_error
  end
end

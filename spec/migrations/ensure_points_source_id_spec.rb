# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261102000100_ensure_points_source_id.rb')

RSpec.describe EnsurePointsSourceId do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(migration).to receive(:sleep)
  end

  after do
    connection.execute('ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer')
    Point.reset_column_information
  end

  def drop_column
    connection.execute('ALTER TABLE points DROP COLUMN source_id')
    Point.reset_column_information
  end

  def stub_alter_raising(error_class, times:)
    attempts = 0
    allow(migration).to receive(:execute).and_call_original
    allow(migration).to receive(:execute).with(/ADD COLUMN IF NOT EXISTS source_id/) do
      attempts += 1
      raise error_class, 'canceling statement due to lock timeout' if attempts <= times

      connection.execute('ALTER TABLE points ADD COLUMN IF NOT EXISTS source_id integer')
    end
    -> { attempts }
  end

  # 20260816150000 recorded itself as applied without the column on busy
  # instances (#3972); this rerun is what finally adds it.
  it 'adds the column the earlier migration left out and starts the backfill' do
    drop_column

    expect { migration.up }.to have_enqueued_job(DataMigrations::BackfillPointDimensionsJob)
    expect(connection.column_exists?(:points, :source_id)).to be true
  end

  # Since 1.17.0 the track builder reads source_id, so these instances built
  # no tracks; the catch-up rebuilds them from the last track onward.
  it 'catches up tracks once it adds the column' do
    drop_column

    expect { migration.up }.to have_enqueued_job(Tracks::DailyGenerationJob)
  end

  it 'keeps existing points when it adds the column' do
    point = create(:point)
    drop_column

    migration.up

    expect(Point.find(point.id).lonlat).to eq(point.lonlat)
  end

  it 'does nothing on an instance that already has the column' do
    expect { migration.up }.not_to have_enqueued_job
  end

  it 'adds the column on Cloud but leaves the backfill for a chosen window' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    drop_column

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::BackfillPointDimensionsJob)
    expect(connection.column_exists?(:points, :source_id)).to be true
  end

  it 'retries a lost lock race instead of failing on the first loss' do
    drop_column
    attempts = stub_alter_raising(ActiveRecord::LockWaitTimeout, times: 2)

    migration.up

    expect(attempts.call).to eq(3)
    expect(connection.column_exists?(:points, :source_id)).to be true
  end

  # Raising keeps the migration unrecorded, so the next boot tries again
  # instead of leaving the schema short for good.
  it 'fails the migration when every attempt loses the lock' do
    drop_column
    stub_alter_raising(ActiveRecord::LockWaitTimeout, times: described_class::MAX_ATTEMPTS)

    expect { migration.up }.to raise_error(ActiveRecord::LockWaitTimeout, /ADD COLUMN IF NOT EXISTS source_id/)
  end

  it 'fails before touching the schema when the job queue is unreachable' do
    drop_column
    allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError, 'Connection refused')

    expect { migration.up }.to raise_error(RedisClient::CannotConnectError)
    expect(connection.column_exists?(:points, :source_id)).to be false
  end
end

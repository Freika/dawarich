# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260914090000_add_lock_versions_to_points_and_tracks.rb')

RSpec.describe AddLockVersionsToPointsAndTracks, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }

  before do
    migration.down
  end

  after do
    migration.up
  end

  it 'adds lock_version to points and tracks' do
    migration.up

    expect(connection.column_exists?(:points, :lock_version, :integer, null: false, default: 0)).to be(true)
    expect(connection.column_exists?(:tracks, :lock_version, :integer, null: false, default: 0)).to be(true)
  end

  it 'is idempotent when the columns already exist' do
    migration.up

    expect { migration.up }.not_to raise_error
  end

  it 'gives up instead of queueing behind a transaction that holds a lock on tracks' do
    stub_const("#{described_class}::LOCK_TIMEOUT", '200ms')
    stub_const("#{described_class}::MAX_ATTEMPTS", 1)
    blocker = ActiveRecord::Base.connection_pool.checkout
    blocker.execute('BEGIN')
    blocker.execute('LOCK TABLE tracks IN ACCESS SHARE MODE')
    connection.execute("SET statement_timeout = '5s'")

    expect { migration.up }.to raise_error(ActiveRecord::LockWaitTimeout)
  ensure
    connection.execute('RESET statement_timeout')
    blocker&.execute('ROLLBACK')
    ActiveRecord::Base.connection_pool.checkin(blocker) if blocker
  end
end

# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261029120000_add_anomaly_override_to_points.rb')

# DDL is transactional in PostgreSQL, so the example's rollback restores the column.
RSpec.describe AddAnomalyOverrideToPoints do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }

  before do
    ActiveRecord::Migration.verbose = false
    migration.migrate(:down)
    Point.reset_column_information
  end

  after do
    ActiveRecord::Migration.verbose = true
    Point.reset_column_information
  end

  it 'keeps existing points and marks them as not overridden' do
    user = create(:user)
    point = create(:point, user:, anomaly: true)

    migration.migrate(:up)
    Point.reset_column_information

    expect(connection.column_exists?(:points, :anomaly_override, :boolean, null: false, default: 'false')).to be(true)
    expect(point.reload).to have_attributes(anomaly: true, anomaly_override: false)
  end

  it 'is a no-op when the column already exists' do
    migration.migrate(:up)

    expect { migration.migrate(:up) }.not_to raise_error
    expect(connection.column_exists?(:points, :anomaly_override, :boolean, null: false, default: 'false')).to be(true)
  end

  it 'rolls back cleanly when the column is already gone' do
    expect { migration.migrate(:down) }.not_to raise_error
    expect(connection.column_exists?(:points, :anomaly_override)).to be(false)
  end
end

RSpec.describe AddAnomalyOverrideToPoints, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }

  before do
    ActiveRecord::Migration.verbose = false
    migration.migrate(:down)
  end

  # Restore directly: stub_const is still active in after hooks, so the
  # migration itself would run with the 200ms timeout and a single attempt.
  after do
    connection.add_column :points, :anomaly_override, :boolean, default: false, null: false, if_not_exists: true
    ActiveRecord::Migration.verbose = true
    Point.reset_column_information
  end

  it 'gives up instead of queueing behind a transaction that holds a lock on points' do
    stub_const("#{described_class}::LOCK_TIMEOUT", '200ms')
    stub_const("#{described_class}::MAX_ATTEMPTS", 1)
    blocker = ActiveRecord::Base.connection_pool.checkout
    blocker.execute('BEGIN')
    blocker.execute('LOCK TABLE points IN ACCESS SHARE MODE')
    connection.execute("SET statement_timeout = '5s'")

    expect { migration.migrate(:up) }.to raise_error(ActiveRecord::LockWaitTimeout)
  ensure
    connection.execute('RESET statement_timeout')
    blocker&.execute('ROLLBACK')
    ActiveRecord::Base.connection_pool.checkin(blocker) if blocker
  end
end

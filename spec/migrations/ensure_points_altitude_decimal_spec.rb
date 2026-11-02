# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261102000200_ensure_points_altitude_decimal.rb')

RSpec.describe EnsurePointsAltitudeDecimal do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  before { allow(migration).to receive(:sleep) }

  after do
    connection.execute('ALTER TABLE points ADD COLUMN IF NOT EXISTS altitude_decimal numeric(10,2)')
    Point.reset_column_information
  end

  def drop_column
    connection.execute('ALTER TABLE points DROP COLUMN altitude_decimal')
    Point.reset_column_information
  end

  def stub_alter_raising(times:)
    attempts = 0
    allow(migration).to receive(:execute).and_call_original
    allow(migration).to receive(:execute).with(/ADD COLUMN IF NOT EXISTS altitude_decimal/) do
      attempts += 1
      raise ActiveRecord::LockWaitTimeout, 'canceling statement due to lock timeout' if attempts <= times

      connection.execute('ALTER TABLE points ADD COLUMN IF NOT EXISTS altitude_decimal numeric(10,2)')
    end
    -> { attempts }
  end

  # Instances first set up from the 1.5.0–1.6.x schema.rb recorded the decimal
  # migration as applied without ever getting the column.
  it 'adds the column with the type the decimal migration gives it' do
    drop_column

    migration.up

    column = Point.columns_hash['altitude_decimal']
    expect([column&.type, column&.precision, column&.scale]).to eq([:decimal, 10, 2])
  end

  it 'keeps existing points when it adds the column' do
    point = create(:point, altitude: 120)
    drop_column

    migration.up

    expect(Point.find(point.id).altitude).to eq(120)
  end

  it 'leaves an instance that already has the column alone' do
    expect(migration).not_to receive(:execute).with(/ADD COLUMN/)

    migration.up
  end

  it 'retries a lost lock race instead of failing on the first loss' do
    drop_column
    attempts = stub_alter_raising(times: 2)

    migration.up

    expect(attempts.call).to eq(3)
    expect(connection.column_exists?(:points, :altitude_decimal)).to be true
  end

  it 'fails the migration when every attempt loses the lock' do
    drop_column
    stub_alter_raising(times: described_class::MAX_ATTEMPTS)

    expect { migration.up }.to raise_error(ActiveRecord::LockWaitTimeout, /ADD COLUMN IF NOT EXISTS altitude_decimal/)
  end
end

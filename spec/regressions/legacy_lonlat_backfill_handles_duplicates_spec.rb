# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260714090000_drop_legacy_lat_lon_from_points.rb')

RSpec.describe 'Legacy coordinate backfill with duplicate points' do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { DropLegacyLatLonFromPoints.new }
  let!(:user) { create(:user) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    # Recreate the pre-upgrade shape without altering the actual points table.
    # PostgreSQL resolves the migration's unqualified points name to this table;
    # the example transaction rolls back both its DDL and its synthetic rows.
    connection.execute <<~SQL
      CREATE TEMP TABLE points (LIKE public.points INCLUDING DEFAULTS) ON COMMIT DROP;
      ALTER TABLE points ADD COLUMN latitude numeric(10,6), ADD COLUMN longitude numeric(10,6);
      CREATE UNIQUE INDEX index_points_on_lonlat_timestamp_user_id
        ON points (lonlat, timestamp, user_id);
    SQL
  end

  def insert_point(id:, converted: false)
    lonlat = converted ? 'ST_SetSRID(ST_MakePoint(-140.654321, -40.123456), 4326)' : 'NULL'
    connection.execute <<~SQL
      INSERT INTO points (id, user_id, timestamp, latitude, longitude, lonlat, created_at, updated_at)
      VALUES (#{id}, #{user.id}, 1700000000, -40.123456, -140.654321, #{lonlat}, NOW(), NOW())
    SQL
  end

  def expect_successful_upgrade
    # A savepoint contains a failed SQL statement so fixture cleanup still runs.
    expect { connection.transaction(requires_new: true) { migration.up } }.not_to raise_error

    expect(connection.column_exists?(:points, :latitude)).to be(false)
    expect(connection.column_exists?(:points, :longitude)).to be(false)
    expect(connection.select_value('SELECT COUNT(*) FROM points WHERE lonlat IS NULL')).to eq(0)
    expect(connection.select_value(<<~SQL)).to eq(1)
      SELECT COUNT(*) FROM points
      WHERE user_id = #{user.id} AND timestamp = 1700000000
        AND lonlat = ST_SetSRID(ST_MakePoint(-140.654321, -40.123456), 4326)::geography
    SQL
  end

  it 'backfills a unique legacy point and drops the legacy columns' do
    insert_point(id: 1001)

    expect_successful_upgrade
  end

  it 'completes the upgrade when two legacy rows have the same position, timestamp and user' do
    insert_point(id: 1001)
    insert_point(id: 1002)
    expect(connection.select_value('SELECT COUNT(*) FROM points WHERE lonlat IS NULL')).to eq(2)

    expect_successful_upgrade
    expect(connection.select_values('SELECT id FROM points')).to eq([1001])
  end

  it 'completes the upgrade when a legacy row duplicates an already converted point' do
    insert_point(id: 1001)
    insert_point(id: 1002, converted: true)
    expect(connection.select_value('SELECT COUNT(*) FROM points WHERE lonlat IS NULL')).to eq(1)

    expect_successful_upgrade
    expect(connection.select_values('SELECT id FROM points')).to eq([1002])
  end

  it 'preserves duplicate metadata and adjusts counters across imports before batched backfill' do
    first_import = create(:import, user:, points_count: 2)
    second_import = create(:import, user:, points_count: 1)
    user.update!(points_count: 3)
    stub_const('DropLegacyLatLonFromPoints::BATCH_SIZE', 1)
    insert_point(id: 1003)
    insert_point(id: 1002)
    insert_point(id: 1001)
    connection.execute <<~SQL
      UPDATE points SET import_id = #{first_import.id} WHERE id IN (1001, 1002);
      UPDATE points SET raw_data = '{"source":"first"}', visit_id = 20, track_id = 40 WHERE id = 1002;
      UPDATE points SET import_id = #{second_import.id}, raw_data = '{"source":"second"}',
        visit_id = 10, track_id = 30 WHERE id = 1003;
    SQL

    expect_successful_upgrade

    expect(connection.select_one('SELECT id, raw_data::text, visit_id, track_id FROM points')).to eq(
      'id' => 1001, 'raw_data' => '{"source": "first"}', 'visit_id' => 10, 'track_id' => 30
    )
    expect(user.reload.points_count).to eq(1)
    expect(first_import.reload.points_count).to eq(1)
    expect(second_import.reload.points_count).to eq(0)

    migration.up

    expect(user.reload.points_count).to eq(1)
    expect(first_import.reload.points_count).to eq(1)
    expect(second_import.reload.points_count).to eq(0)
  end

  it 'fills missing metadata on an already converted keeper without replacing existing values' do
    insert_point(id: 1001)
    insert_point(id: 1002, converted: true)
    connection.execute <<~SQL
      UPDATE points SET raw_data = '{"source":"duplicate"}', visit_id = 10, track_id = 30 WHERE id = 1001;
      UPDATE points SET raw_data = '{"source":"keeper"}', visit_id = 20 WHERE id = 1002;
    SQL

    expect_successful_upgrade

    expect(connection.select_one('SELECT id, raw_data::text, visit_id, track_id FROM points')).to eq(
      'id' => 1002, 'raw_data' => '{"source": "keeper"}', 'visit_id' => 20, 'track_id' => 30
    )
    expect(user.reload.points_count).to eq(0)
  end

  it 'keeps empty raw data when no duplicate contains metadata' do
    insert_point(id: 1001)
    insert_point(id: 1002)

    expect_successful_upgrade

    expect(connection.select_value('SELECT raw_data::text FROM points')).to eq('{}')
  end

  it 'keeps points with different users, timestamps or coordinates and incomplete legacy coordinates' do
    other_user = create(:user)
    (1001..1005).each { |id| insert_point(id:) }
    connection.execute <<~SQL
      UPDATE points SET user_id = #{other_user.id} WHERE id = 1002;
      UPDATE points SET timestamp = 1700000001 WHERE id = 1003;
      UPDATE points SET longitude = -140.654322 WHERE id = 1004;
      UPDATE points SET latitude = NULL WHERE id = 1005;
    SQL

    migration.up

    expect(connection.select_values('SELECT id FROM points ORDER BY id')).to eq((1001..1005).to_a)
    expect(connection.select_values('SELECT id FROM points WHERE lonlat IS NULL')).to eq([1005])
    expect(connection.column_exists?(:points, :latitude)).to be(false)
    expect(connection.column_exists?(:points, :longitude)).to be(false)
  end
end

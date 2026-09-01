# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260901100000_create_points_v2.rb')
require Rails.root.join('db/migrate/20260901110000_rewrite_points_to_v2.rb')

RSpec.describe RewritePointsToV2, :non_transactional do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }
  let(:user) { create(:user) }

  before do
    PointsV1Schema.install_v1_points
    connection.execute('DROP TABLE IF EXISTS points_v2 CASCADE')
    CreatePointsV2.new.up
  end

  after do
    %w[points_v2 points_v2_changes points_v2_rewrite_state].each do |table|
      connection.execute("DROP TABLE IF EXISTS #{table} CASCADE")
    end
    connection.execute('DROP TRIGGER IF EXISTS points_v2_capture ON points')
    connection.execute('DROP FUNCTION IF EXISTS points_v2_capture()')
    PointsV1Schema.restore_real_points
  end

  def seed_v1_point(timestamp:, city: nil)
    connection.select_value(<<~SQL)
      INSERT INTO points ("timestamp", user_id, city, lonlat, created_at, updated_at)
      VALUES (#{timestamp}, #{user.id}, #{connection.quote(city)},
              'POINT(12.3712 51.3402)', NOW(), NOW())
      RETURNING id
    SQL
  end

  it 'swaps points to the v2 shape and keeps the old table as points_legacy_d' do
    seed_v1_point(timestamp: 1_700_000_000, city: 'Leipzig')

    migration.up

    expect(connection.column_exists?(:points, :country_name)).to be(false)
    expect(connection.select_value(%(SELECT "timestamp" FROM points LIMIT 1))).to eq(1_700_000_000)
    expect(connection.table_exists?('points_legacy_d')).to be(true)
    expect(connection.select_value('SELECT COUNT(*) FROM points_legacy_d').to_i).to eq(1)
  end

  it 'renames the v2 indexes and constraints to their canonical v1 names' do
    seed_v1_point(timestamp: 1_700_000_100)

    migration.up

    names = connection.select_values("SELECT indexname FROM pg_indexes WHERE tablename = 'points'")
    expect(names).to include('points_pkey', 'index_points_on_lonlat',
                             'index_points_on_user_id_timestamp_lonlat',
                             'idx_points_track_id_timestamp', 'index_points_on_unarchived')
    expect(names.grep(/_v2/)).to be_empty

    fk_names = connection.select_values(<<~SQL)
      SELECT conname FROM pg_constraint
      WHERE conrelid = 'points'::regclass AND contype = 'f'
    SQL
    expect(fk_names).to match_array(%w[fk_points_raw_data_archive fk_points_track
                                       fk_points_user fk_points_visit])
  end

  it 'moves the sequence so post-swap inserts keep working' do
    seed_v1_point(timestamp: 1_700_000_200)

    migration.up

    new_id = connection.select_value(<<~SQL)
      INSERT INTO points (id, "timestamp", user_id, created_at, updated_at)
      VALUES (nextval('points_id_seq'), 2200000000, #{user.id}, NOW(), NOW())
      RETURNING id
    SQL
    expect(new_id).to be_present
  end

  it 'applies writes that raced the copy before renaming' do
    copied = seed_v1_point(timestamp: 1_700_000_300)

    job = DataMigrations::RewritePointsV2Job.new
    job.run_phases_through_copy
    job.finish
    late = seed_v1_point(timestamp: 1_700_000_360)
    connection.execute("UPDATE points SET city = 'Leipzig' WHERE id = #{copied}")

    migration.up

    expect(connection.select_value("SELECT city FROM points WHERE id = #{copied}")).to eq('Leipzig')
    expect(connection.select_value("SELECT COUNT(*) FROM points WHERE id = #{late}").to_i).to eq(1)
  end

  it 'leaves no rewrite machinery behind' do
    seed_v1_point(timestamp: 1_700_000_400)

    migration.up

    expect(connection.table_exists?('points_v2')).to be(false)
    expect(connection.table_exists?('points_v2_changes')).to be(false)
    expect(connection.table_exists?('points_v2_rewrite_state')).to be(false)
    expect(connection.select_value(
      "SELECT COUNT(*) FROM pg_trigger WHERE tgname = 'points_v2_capture'"
    ).to_i).to eq(0)
  end

  it 'is a no-op on second run' do
    seed_v1_point(timestamp: 1_700_000_500)
    migration.up

    expect { migration.up }.not_to raise_error
    expect(connection.select_value('SELECT COUNT(*) FROM points').to_i).to eq(1)
  end

  it 'swaps instantly on an empty database (fresh install)' do
    migration.up

    expect(connection.column_exists?(:points, :country_name)).to be(false)
    expect(connection.select_value('SELECT COUNT(*) FROM points').to_i).to eq(0)
  end

  it 'restores the v1 table on down' do
    seed_v1_point(timestamp: 1_700_000_600)
    migration.up

    migration.down

    expect(connection.column_exists?(:points, :country_name)).to be(true)
    expect(connection.select_value('SELECT COUNT(*) FROM points').to_i).to eq(1)
  end
end

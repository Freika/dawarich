# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A12d2 Rails backfill schema' do
  it 'Rails setup installs and cleans both typed backfill tables' do
    connection = ActiveRecord::Base.connection
    public_tables = connection.select_values(
      "SELECT table_name FROM information_schema.tables WHERE table_schema='public'"
    )
    phoenix_state!
    tables = %w[track_backfill_ranges track_backfill_walks]
    tables.each do |table|
      expect(connection.select_value("SELECT to_regclass('phoenix.#{table}') IS NOT NULL")).to be(true)
    end
    fields = connection.select_rows(<<~SQL.squish)
      SELECT column_name, data_type, is_nullable FROM information_schema.columns
      WHERE table_schema='phoenix' AND table_name='track_backfill_walks'
    SQL
    %w[selected_start_timestamp selected_end_timestamp].each do |field|
      expect(fields).to include([field, 'bigint', 'YES'])
    end
    connection.execute(<<~SQL.squish)
      INSERT INTO phoenix.track_backfill_ranges
        (user_id, earliest_timestamp, latest_timestamp, cycle_id, time_zone, due_at, expires_at)
      VALUES (48001, 10, 20, '00000000-0000-4000-8000-000000480001', 'Etc/UTC', now(), now())
    SQL
    connection.execute(<<~SQL.squish)
      INSERT INTO phoenix.track_backfill_walks (user_id, walk_id, state, time_zone, expires_at)
      VALUES (48001, '00000000-0000-4000-8000-000000480002', 'walking', 'Etc/UTC', now())
    SQL
    PhoenixTables.install_state!
    tables.each { expect(connection.select_value("SELECT count(*) FROM phoenix.#{_1}")).to eq(0) }
    without_phoenix_state!
    tables.each do |table|
      expect(connection.select_value("SELECT to_regclass('phoenix.#{table}') IS NOT NULL")).to be(false)
    end
    phoenix_state!
    tables.each do |table|
      expect(connection.select_value("SELECT to_regclass('phoenix.#{table}') IS NOT NULL")).to be(true)
    end
    expect(connection.select_values("SELECT table_name FROM information_schema.tables WHERE table_schema='public'"))
      .to match_array(public_tables)
  ensure
    PhoenixSchema.reset!
  end
end

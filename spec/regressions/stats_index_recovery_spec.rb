# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20251208210410_add_composite_index_to_stats')
require Rails.root.join('db/migrate/20260906103000_repair_invalid_stats_unique_index')

RSpec.describe 'Stats uniqueness after an interrupted upgrade' do
  self.use_transactional_tests = false

  let(:connection) { ActiveRecord::Base.connection }
  let(:index_name) { 'index_stats_on_user_id_year_month' }

  around do |example|
    schema = "stats_recovery_#{SecureRandom.hex(6)}"
    original_path = connection.schema_search_path
    connection.execute("CREATE SCHEMA #{schema}")
    connection.schema_search_path = "#{schema},public"
    connection.execute(<<~SQL)
      CREATE TABLE stats (
        id bigserial PRIMARY KEY, user_id bigint NOT NULL, year integer NOT NULL, month integer NOT NULL
      )
    SQL
    example.run
  ensure
    connection.schema_search_path = original_path
    connection.execute("DROP SCHEMA #{schema} CASCADE")
  end

  it 'replaces a failed concurrent index on retry and enforces uniqueness' do
    seed_duplicates
    expect { create_index }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(index_valid?).to be(false)
    expected = connection.select_values('SELECT max(id) FROM stats GROUP BY user_id, year, month ORDER BY max(id)')

    2.times { AddCompositeIndexToStats.new.migrate(:up) }

    expect(connection.select_values('SELECT id FROM stats ORDER BY id')).to eq(expected)
    expect(index_valid?).to be(true)
    expect { insert_duplicate }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'repairs an invalid index even after the original migration was recorded as complete' do
    seed_duplicates
    expect { create_index }.to raise_error(ActiveRecord::RecordNotUnique)
    connection.execute('CREATE TABLE schema_migrations (version varchar NOT NULL PRIMARY KEY)')
    connection.execute("INSERT INTO schema_migrations (version) VALUES ('20251208210410')")
    expected = connection.select_values('SELECT max(id) FROM stats GROUP BY user_id, year, month ORDER BY max(id)')

    2.times { RepairInvalidStatsUniqueIndex.new.migrate(:up) }

    expect(connection.select_values('SELECT id FROM stats ORDER BY id')).to eq(expected)
    expect(index_valid?).to be(true)
    expect(connection.select_values('SELECT version FROM schema_migrations')).to eq(['20251208210410'])
    expect { insert_duplicate }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'does not rebuild a healthy index or delete existing records' do
    connection.execute('INSERT INTO stats (user_id, year, month) VALUES (1, 2024, 1), (1, 2024, 2)')
    create_index
    original_oid = connection.select_value("SELECT '#{index_name}'::regclass::oid")
    original_rows = connection.select_all('SELECT * FROM stats ORDER BY id').to_a

    RepairInvalidStatsUniqueIndex.new.migrate(:up)

    expect(connection.select_value("SELECT '#{index_name}'::regclass::oid")).to eq(original_oid)
    expect(connection.select_all('SELECT * FROM stats ORDER BY id').to_a).to eq(original_rows)
  end

  it 'creates a missing index after deduplicating records' do
    seed_duplicates

    RepairInvalidStatsUniqueIndex.new.migrate(:up)

    expect(index_valid?).to be(true)
    expect(connection.select_value('SELECT count(*) FROM stats')).to eq(3)
    expect { insert_duplicate }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  def seed_duplicates
    connection.execute('INSERT INTO stats (user_id, year, month) SELECT 1, 2024, 1 FROM generate_series(1, 1005)')
    connection.execute('INSERT INTO stats (user_id, year, month) VALUES (2, 2024, 1), (2, 2024, 1), (1, 2024, 2)')
  end

  def create_index
    connection.execute("CREATE UNIQUE INDEX CONCURRENTLY #{index_name} ON stats (user_id, year, month)")
  end

  def index_valid?
    connection.select_value("SELECT indisvalid FROM pg_index WHERE indexrelid = '#{index_name}'::regclass")
  end

  def insert_duplicate
    connection.execute('INSERT INTO stats (user_id, year, month) VALUES (1, 2024, 1)')
  end
end

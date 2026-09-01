# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260901100000_create_points_v2.rb')

RSpec.describe CreatePointsV2, :non_transactional do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  # The frozen v2 column list, in frozen (alignment-descending) order.
  # Authority: superpowers/plans/2026-08-31-points-v2-column-freeze.md
  let(:frozen_columns) do
    [
      ['id', 'bigint', 'NO'],
      ['timestamp',           'bigint',                      'NO'],
      ['user_id',             'bigint',                      'NO'],
      ['track_id',            'bigint',                      'YES'],
      ['import_id',           'bigint',                      'YES'],
      ['visit_id',            'bigint',                      'YES'],
      ['raw_data_archive_id', 'bigint',                      'YES'],
      ['created_at',          'timestamp without time zone', 'NO'],
      ['updated_at',          'timestamp without time zone', 'NO'],
      ['reverse_geocoded_at', 'timestamp without time zone', 'YES'],
      ['country_id',          'integer',                     'YES'],
      ['source_id',           'integer',                     'YES'],
      ['accuracy',            'integer',                     'YES'],
      ['vertical_accuracy',   'integer',                     'YES'],
      ['altitude',            'real',                        'YES'],
      ['velocity',            'real',                        'YES'],
      ['course',              'real',                        'YES'],
      ['course_accuracy',     'real',                        'YES'],
      ['battery',             'smallint',                    'YES'],
      ['anomaly',             'boolean',                     'YES'],
      ['raw_data_archived',   'boolean',                     'NO'],
      ['lonlat',              'USER-DEFINED',                'YES'],
      ['city',                'character varying',           'YES'],
      ['geodata',             'jsonb',                       'NO'],
      ['raw_data',            'jsonb',                       'YES'],
      ['motion_data', 'jsonb', 'NO']
    ]
  end

  after do
    connection.execute('DROP TABLE IF EXISTS points_v2')
  end

  def column_rows
    connection.select_rows(<<~SQL)
      SELECT column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_name = 'points_v2'
      ORDER BY ordinal_position
    SQL
  end

  it 'creates points_v2 with exactly the frozen columns, types and order' do
    migration.up

    expect(column_rows).to eq(frozen_columns)
  end

  it 'stores lonlat as PostGIS geography' do
    migration.up

    udt = connection.select_value(<<~SQL)
      SELECT udt_name FROM information_schema.columns
      WHERE table_name = 'points_v2' AND column_name = 'lonlat'
    SQL
    expect(udt).to eq('geography')
  end

  it 'gives points_v2 a primary key on id continuing the points sequence' do
    migration.up

    pk = connection.select_value(<<~SQL)
      SELECT a.attname
      FROM pg_index i
      JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
      WHERE i.indrelid = 'points_v2'::regclass AND i.indisprimary
    SQL
    expect(pk).to eq('id')

    default = connection.select_value(<<~SQL)
      SELECT column_default FROM information_schema.columns
      WHERE table_name = 'points_v2' AND column_name = 'id'
    SQL
    expect(default).to include("nextval('points_id_seq'")
  end

  it 'is idempotent' do
    migration.up

    expect { migration.up }.not_to raise_error
  end

  it 'no-ops when points is already v2-shaped' do
    allow(migration).to receive(:v1_points?).and_return(false)

    migration.up

    expect(connection.table_exists?('points_v2')).to be(false)
  end

  it 'carries the jsonb and boolean defaults' do
    migration.up

    defaults = connection.select_rows(<<~SQL).to_h
      SELECT column_name, column_default FROM information_schema.columns
      WHERE table_name = 'points_v2'
        AND column_name IN ('geodata', 'raw_data', 'motion_data', 'raw_data_archived')
    SQL
    expect(defaults['geodata']).to include("'{}'::jsonb")
    expect(defaults['raw_data']).to include("'{}'::jsonb")
    expect(defaults['motion_data']).to include("'{}'::jsonb")
    expect(defaults['raw_data_archived']).to eq('false')
  end
end

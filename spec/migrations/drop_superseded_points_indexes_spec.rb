# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260816120000_drop_superseded_points_indexes.rb')

RSpec.describe DropSupersededPointsIndexes, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration)  { described_class.new }
  let(:superseded_index_names) do
    %w[
      index_points_on_lonlat_timestamp_user_id
      index_points_on_user_id_and_timestamp
      idx_points_user_country_name
    ]
  end

  let(:replacement_index_name) { 'index_points_on_user_id_timestamp_lonlat' }

  before do
    PointsV1Schema.install_v1_points
    migration.down
  end

  after do
    migration.up
    PointsV1Schema.restore_real_points
  end

  describe '#up' do
    it 'starts from a state where the superseded indexes actually exist' do
      expect(points_index_names).to include(*superseded_index_names)
    end

    it 'drops the three superseded indexes' do
      migration.up

      expect(points_index_names).not_to include(*superseded_index_names)
    end

    it 'keeps the replacement unique index' do
      migration.up

      expect(points_index_names).to include(replacement_index_name)
    end

    it 'is idempotent when the indexes are already gone' do
      migration.up

      expect { migration.up }.not_to raise_error
    end

    it 'clears a restrictive session lock_timeout before touching indexes' do
      connection.execute("SET lock_timeout = '5s'")

      migration.up

      expect(connection.select_value('SHOW lock_timeout')).to eq('0')
    end

    context 'with a leftover invalid index' do
      let(:test_index_name) { 'tmp_test_orphan_points_idx' }

      before do
        connection.execute("DROP INDEX IF EXISTS #{test_index_name}")
        connection.execute("CREATE INDEX #{test_index_name} ON points (city)")
        connection.execute(<<~SQL)
          UPDATE pg_index
          SET indisvalid = false
          WHERE indexrelid = '#{test_index_name}'::regclass
        SQL
      end

      after do
        connection.execute("DROP INDEX IF EXISTS #{test_index_name}")
      end

      it 'sweeps the invalid index before dropping' do
        migration.up

        still_present = connection.select_value(
          "SELECT 1 FROM pg_class WHERE relname = '#{test_index_name}'"
        )
        expect(still_present).to be_nil
      end
    end

    context 'when the replacement index is invalid' do
      before do
        connection.execute(<<~SQL)
          UPDATE pg_index
          SET indisvalid = false
          WHERE indexrelid = '#{replacement_index_name}'::regclass
        SQL
      end

      after do
        connection.execute(<<~SQL)
          UPDATE pg_index
          SET indisvalid = true
          WHERE indexrelid = '#{replacement_index_name}'::regclass
        SQL
      end

      it 'repairs the replacement index instead of refusing to run' do
        migration.up

        valid = connection.select_value(<<~SQL)
          SELECT i.indisvalid
          FROM pg_index i
          JOIN pg_class c ON c.oid = i.indexrelid
          WHERE c.relname = '#{replacement_index_name}'
        SQL
        expect(valid).to be(true)
      end

      it 'drops the superseded indexes after the repair' do
        migration.up

        expect(points_index_names).not_to include(*superseded_index_names)
      end
    end

    context 'when the replacement index is missing' do
      before do
        connection.execute("DROP INDEX IF EXISTS #{replacement_index_name}")
      end

      after do
        connection.execute(<<~SQL)
          CREATE UNIQUE INDEX IF NOT EXISTS #{replacement_index_name}
          ON points (user_id, timestamp, lonlat)
        SQL
      end

      it 'refuses to run' do
        expect { migration.up }
          .to raise_error(ActiveRecord::MigrationError, /#{replacement_index_name}/)
      end

      it 'leaves the superseded indexes in place' do
        suppress(ActiveRecord::MigrationError) { migration.up }

        expect(points_index_names).to include(*superseded_index_names)
      end
    end
  end

  describe '#down' do
    it 'restores the three superseded index definitions' do
      migration.up
      migration.down

      expect(points_index_names).to include(*superseded_index_names)
    end

    it 'is idempotent when the indexes are already present' do
      expect { migration.down }.not_to raise_error
    end
  end

  def points_index_names
    connection.select_values(<<~SQL)
      SELECT c.relname
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_class t ON t.oid = i.indrelid
      WHERE t.relname = 'points'
    SQL
  end
end

# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20251228000000_remove_unused_indexes.rb')

RSpec.describe RemoveUnusedIndexes, :non_transactional do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration)  { described_class.new }
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

  describe '#drop_invalid_indexes_on_points!' do
    it 'drops indexes on points that are marked indisvalid' do
      migration.drop_invalid_indexes_on_points!

      still_present = connection.select_value(
        "SELECT 1 FROM pg_class WHERE relname = '#{test_index_name}'"
      )
      expect(still_present).to be_nil
    end

    it 'leaves valid indexes on points untouched' do
      valid_before = points_valid_index_names

      migration.drop_invalid_indexes_on_points!

      expect(points_valid_index_names).to match_array(valid_before)
    end

    it 'is a no-op when there are no invalid indexes' do
      connection.execute("DROP INDEX IF EXISTS #{test_index_name}")

      expect { migration.drop_invalid_indexes_on_points! }.not_to raise_error
    end
  end

  def points_valid_index_names
    connection.select_values(<<~SQL)
      SELECT c.relname
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_class t ON t.oid = i.indrelid
      WHERE t.relname = 'points' AND i.indisvalid
    SQL
  end
end

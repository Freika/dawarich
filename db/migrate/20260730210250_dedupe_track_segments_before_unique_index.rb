# frozen_string_literal: true

class DedupeTrackSegmentsBeforeUniqueIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 500
  PLAN_TABLE = 'track_segment_dedupe_plan'

  # The losers are identified once. Re-deriving them per batch re-ran a full
  # row_number() sort of `track_segments` just to fetch 500 ids, so N duplicates
  # cost N/500 whole-table sorts while db:migrate blocks container boot.
  def up
    build_plan
    delete_planned_losers
  ensure
    execute("DROP TABLE IF EXISTS #{PLAN_TABLE}")
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def build_plan
    execute("DROP TABLE IF EXISTS #{PLAN_TABLE}")
    execute(<<~SQL.squish)
      CREATE TEMPORARY TABLE #{PLAN_TABLE} AS
      SELECT id FROM (
        SELECT id,
               row_number() OVER (PARTITION BY track_id, start_index ORDER BY id) AS position
        FROM track_segments
      ) ranked
      WHERE ranked.position > 1
    SQL
  end

  def delete_planned_losers
    loop do
      ids = execute("SELECT id FROM #{PLAN_TABLE} LIMIT #{BATCH_SIZE}").to_a.map { |row| row['id'].to_i }
      break if ids.empty?

      list = ids.join(',')
      execute("DELETE FROM track_segments WHERE id IN (#{list})")
      execute("DELETE FROM #{PLAN_TABLE} WHERE id IN (#{list})")
    end
  end
end

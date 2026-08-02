# frozen_string_literal: true

class DedupeTrackSegmentsBeforeUniqueIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 500

  def up
    loop do
      loser_ids = duplicate_loser_ids
      break if loser_ids.empty?

      execute("DELETE FROM track_segments WHERE id IN (#{loser_ids.join(',')})")
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def duplicate_loser_ids
    execute(<<~SQL.squish).to_a.map { |row| row['id'].to_i }
      SELECT id FROM (
        SELECT id,
               row_number() OVER (PARTITION BY track_id, start_index ORDER BY id) AS position
        FROM track_segments
      ) ranked
      WHERE ranked.position > 1
      LIMIT #{BATCH_SIZE}
    SQL
  end
end

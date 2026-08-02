# frozen_string_literal: true

class DedupeVisitsBeforeUniqueIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 500
  PLAN_TABLE = 'visit_dedupe_plan'

  # The plan is computed once. Re-deriving it per batch re-ran a full GROUP BY
  # over `visits` just to fetch 500 ids, so N duplicates cost N/500 whole-table
  # aggregations — all of it while db:migrate blocks container boot.
  def up
    build_plan
    collapse_planned_groups
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
      SELECT min(id) AS keeper, array_agg(id) AS ids
      FROM visits
      WHERE place_id IS NOT NULL
      GROUP BY user_id, started_at, place_id
      HAVING count(*) > 1
    SQL
  end

  def collapse_planned_groups
    loop do
      rows = execute("SELECT keeper, ids FROM #{PLAN_TABLE} LIMIT #{BATCH_SIZE}").to_a
      break if rows.empty?

      keepers = rows.map { |row| row['keeper'].to_i }

      rows.each do |row|
        keeper = row['keeper'].to_i
        losers = parse_ids(row['ids']) - [keeper]
        collapse(keeper, losers) if losers.any?
      end

      execute("DELETE FROM #{PLAN_TABLE} WHERE keeper IN (#{keepers.join(',')})")
    end
  end

  def parse_ids(value)
    return value.map(&:to_i) if value.is_a?(Array)

    value.to_s.delete('{}').split(',').map(&:to_i)
  end

  def collapse(keeper_id, loser_ids)
    Visit.transaction do
      Point.where(visit_id: loser_ids).update_all(visit_id: keeper_id)
      execute("DELETE FROM place_visits WHERE visit_id IN (#{loser_ids.join(',')})")
      execute("DELETE FROM visits WHERE id IN (#{loser_ids.join(',')})")
    end
  end
end

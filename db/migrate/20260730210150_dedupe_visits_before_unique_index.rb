# frozen_string_literal: true

class DedupeVisitsBeforeUniqueIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 500

  def up
    loop do
      groups = duplicate_groups
      break if groups.empty?

      groups.each { |keeper_id, loser_ids| collapse(keeper_id, loser_ids) }
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def duplicate_groups
    rows = execute(<<~SQL.squish).to_a
      SELECT min(id) AS keeper, array_agg(id) AS ids
      FROM visits
      WHERE place_id IS NOT NULL
      GROUP BY user_id, started_at, place_id
      HAVING count(*) > 1
      LIMIT #{BATCH_SIZE}
    SQL

    pairs = rows.map do |row|
      keeper = row['keeper'].to_i
      [keeper, parse_ids(row['ids']) - [keeper]]
    end

    pairs.reject { |_, ids| ids.empty? }
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

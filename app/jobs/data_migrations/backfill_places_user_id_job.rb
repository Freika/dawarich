# frozen_string_literal: true

class DataMigrations::BackfillPlacesUserIdJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 1_000

  def perform(batch_size: BATCH_SIZE)
    pending = Place.where(user_id: nil).count
    if pending.zero?
      Rails.logger.info("[#{self.class}] no places with NULL user_id, skipping")
      return
    end

    Rails.logger.info("[#{self.class}] starting; pending=#{pending} batch_size=#{batch_size}")

    assigned_total = 0
    deleted_total = 0

    loop do
      batch_ids = Place.where(user_id: nil).order(:id).limit(batch_size).pluck(:id)
      break if batch_ids.empty?

      assigned_ids = assign_winners(batch_ids)
      orphan_ids = batch_ids - assigned_ids
      deleted_count = delete_orphans(orphan_ids)

      assigned_total += assigned_ids.size
      deleted_total += deleted_count

      if assigned_ids.empty? && deleted_count.zero?
        Rails.logger.warn("[#{self.class}] batch made no progress, aborting to avoid infinite loop")
        break
      end
    end

    Rails.logger.info(
      "[#{self.class}] done; assigned=#{assigned_total} deleted=#{deleted_total}"
    )
  end

  private

  # Bulk-assigns user_id to every place in `place_ids` that has at least one
  # visit (via place_visits OR visits.place_id). The winner is the user with
  # the most visits, tie-broken by most recent started_at, then user_id ASC.
  # Returns the IDs of places that were updated.
  def assign_winners(place_ids)
    return [] if place_ids.empty?

    ids_csv = place_ids.join(',')
    sql = <<~SQL.squish
      WITH counts AS (
        SELECT visits.user_id AS user_id, visits.started_at AS ts, pv.place_id AS place_id
        FROM place_visits pv
        JOIN visits ON visits.id = pv.visit_id
        WHERE pv.place_id IN (#{ids_csv})
        UNION ALL
        SELECT v.user_id, v.started_at, v.place_id
        FROM visits v
        WHERE v.place_id IN (#{ids_csv})
      ),
      ranked AS (
        SELECT place_id, user_id,
          ROW_NUMBER() OVER (
            PARTITION BY place_id
            ORDER BY COUNT(*) DESC, MAX(ts) DESC, user_id ASC
          ) AS rn
        FROM counts
        GROUP BY place_id, user_id
      )
      UPDATE places
      SET user_id = ranked.user_id, updated_at = NOW()
      FROM ranked
      WHERE places.id = ranked.place_id
        AND ranked.rn = 1
        AND places.user_id IS NULL
      RETURNING places.id
    SQL

    result = ActiveRecord::Base.connection.execute(sql)
    result.map { |row| row['id'].to_i }
  end

  def delete_orphans(place_ids)
    return 0 if place_ids.empty?

    Place.where(id: place_ids, user_id: nil).delete_all
  end
end

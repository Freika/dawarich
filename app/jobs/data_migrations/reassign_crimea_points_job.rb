# frozen_string_literal: true

# The bundled country source used Natural Earth's de facto edition, which files
# Crimea under Russia; it now files it under Ukraine, matching the UA-43/UA-40
# subdivisions. Points already resolved to Russia inside the peninsula follow.
class DataMigrations::ReassignCrimeaPointsJob < ApplicationJob
  queue_as :data_migrations

  # Bounding box of the peninsula. The GiST index on lonlat narrows by box
  # first; the Ukraine polygon decides, so the Taman shore stays Russian.
  CRIMEA_BOX = [32.4, 44.3, 36.7, 46.3].freeze
  BATCH_SIZE = 10_000

  def perform
    ukraine = Country.where(iso_a2: 'UA').order(:id).first
    russia_ids = Country.where(iso_a2: 'RU').ids
    return if ukraine.nil? || russia_ids.empty?

    user_ids = Set.new
    loop do
      rows = reassign_batch(ukraine, russia_ids)
      break if rows.empty?

      # Scheduled per batch: moved points no longer match, so a rerun after a
      # crash could not find these users again. The check job debounces.
      rows.each do |user_id, day|
        timestamp = day.to_i * 1.day.to_i
        Stats::GeocodedDays.mark(user_id, timestamp)
        Achievements::CheckJob.schedule(user_id, oldest_timestamp: timestamp)
        user_ids << user_id
      end
    end

    Rails.logger.info("[ReassignCrimeaPoints] moved points for #{user_ids.size} users")
  end

  private

  REASSIGN_SQL = <<~SQL.squish
    WITH batch AS (
      SELECT p.id FROM points p
      WHERE p.country_id IN (:russia_ids)
        AND ST_Intersects(p.lonlat, ST_MakeEnvelope(:west, :south, :east, :north, 4326)::geography)
        AND ST_Covers((SELECT geom FROM countries WHERE id = :ukraine_id), p.lonlat::geometry)
      LIMIT :limit
    ),
    moved AS (
      UPDATE points p SET country_id = :ukraine_id, updated_at = NOW()
      FROM batch WHERE p.id = batch.id
      RETURNING p.user_id, p."timestamp" / 86400 AS day
    )
    SELECT DISTINCT user_id, day FROM moved
  SQL

  def reassign_batch(ukraine, russia_ids)
    west, south, east, north = CRIMEA_BOX
    binds = { russia_ids:, west:, south:, east:, north:, ukraine_id: ukraine.id, limit: BATCH_SIZE }

    ActiveRecord::Base.connection.select_rows(ActiveRecord::Base.sanitize_sql_array([REASSIGN_SQL, binds]))
  end
end

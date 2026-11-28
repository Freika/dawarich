# frozen_string_literal: true

# Points resolved before the bundled boundaries were reloaded move to the
# country whose polygon now covers them.
class DataMigrations::ReassignBoundaryPointsJob < ApplicationJob
  queue_as :data_migrations

  SOURCE_CODE = 'RU'
  TARGET_CODE = 'UA'
  # The GiST index on lonlat narrows by box first; the target polygon decides.
  REGION_BOX = [32.4, 44.3, 36.7, 46.3].freeze
  BATCH_SIZE = 10_000

  def perform
    target = Country.where(iso_a2: TARGET_CODE).order(:id).first
    sources = Country.where(iso_a2: SOURCE_CODE)
    return if target.nil? || sources.none?

    user_ids = Set.new
    loop do
      rows = reassign_batch(target, sources.ids, sources.pluck(:name))
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

    Rails.logger.info("[ReassignBoundaryPoints] moved points for #{user_ids.size} users")
  end

  private

  REASSIGN_SQL = <<~SQL.squish
    WITH batch AS (
      SELECT p.id FROM points p
      WHERE p.country_id IN (:source_ids)
        AND ST_Intersects(p.lonlat, ST_MakeEnvelope(:west, :south, :east, :north, 4326)::geography)
        AND ST_Covers((SELECT geom FROM countries WHERE id = :target_id), p.lonlat::geometry)
      LIMIT :limit
    ),
    moved AS (
      UPDATE points p
      SET country_id = :target_id,
          country_name = CASE WHEN COALESCE(p.country_name, '') IN ('', :source_names) THEN :target_name
                              ELSE p.country_name END,
          country = CASE WHEN COALESCE(p.country, '') IN ('', :source_names) THEN :target_name ELSE p.country END,
          updated_at = NOW()
      FROM batch WHERE p.id = batch.id
      RETURNING p.user_id, p."timestamp" / 86400 AS day
    )
    SELECT DISTINCT user_id, day FROM moved
  SQL

  # Labels left by the country backfill follow the move; other reverse-geocoder
  # labels are provider data and stay as returned.
  def reassign_batch(target, source_ids, source_names)
    west, south, east, north = REGION_BOX
    binds = { source_ids:, source_names:, west:, south:, east:, north:,
              target_id: target.id, target_name: target.name, limit: BATCH_SIZE }

    ActiveRecord::Base.connection.select_rows(ActiveRecord::Base.sanitize_sql_array([REASSIGN_SQL, binds]))
  end
end

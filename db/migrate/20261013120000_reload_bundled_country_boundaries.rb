# frozen_string_literal: true

# Seeds only run on an empty countries table, so existing installs keep the
# old geometry until it is reloaded from the corrected bundled source.
class ReloadBundledCountryBoundaries < ActiveRecord::Migration[8.1]
  # The job reads the reloaded polygons, so it must not be enqueued before
  # the geometry commits: jobs are pushed to Sidekiq immediately here.
  disable_ddl_transaction!

  SOURCE = 'lib/assets/countries.geojson.gz'
  CODES = %w[UA RU].freeze

  def up
    return unless select_value('SELECT EXISTS (SELECT 1 FROM countries)')

    transaction { reload_geometry }
    Rails.cache.delete('dawarich/countries_codes')
    enqueue_reassignment
  end

  def down; end

  private

  def reload_geometry
    source = Zlib::GzipReader.open(Rails.root.join(SOURCE)) { |gzip| JSON.parse(gzip.read) }

    source['features'].each do |feature|
      code = feature.dig('properties', 'ISO3166-1-Alpha-2')
      next unless CODES.include?(code)

      execute ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, feature['geometry'].to_json, code])
        UPDATE countries
        SET geom = ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(?), 4326)), updated_at = NOW()
        WHERE iso_a2 = ?
      SQL
    end
  end

  def enqueue_reassignment
    DataMigrations::ReassignBoundaryPointsJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.error(
      "[ReloadBundledCountryBoundaries] could not enqueue the point reassignment (#{e.class}: #{e.message}). " \
      'Start it later with: DataMigrations::ReassignBoundaryPointsJob.perform_later'
    )
  end
end

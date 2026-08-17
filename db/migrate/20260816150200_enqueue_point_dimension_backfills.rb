# frozen_string_literal: true

class EnqueuePointDimensionBackfills < ActiveRecord::Migration[8.0]
  def up
    # Escape hatch for constrained installs: run the backfill jobs manually via
    # DataMigrations::BackfillPointDimensionsJob.perform_later and
    # DataMigrations::BackfillPointCountryIdJob.perform_later.
    return if ENV['SKIP_POINT_DIMENSION_BACKFILL'].present?

    DataMigrations::BackfillPointDimensionsJob.perform_later if defined?(DataMigrations::BackfillPointDimensionsJob)
    DataMigrations::BackfillPointCountryIdJob.perform_later if defined?(DataMigrations::BackfillPointCountryIdJob)
  rescue StandardError => e
    Rails.logger.warn(
      '[EnqueuePointDimensionBackfills] enqueue failed, run the backfill jobs manually: ' \
      "#{e.class}: #{e.message}"
    )
  end

  def down; end
end

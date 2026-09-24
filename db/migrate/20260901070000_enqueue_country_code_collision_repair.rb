# frozen_string_literal: true

class EnqueueCountryCodeCollisionRepair < ActiveRecord::Migration[8.0]
  def up
    return unless DataMigrations::AddPointDimensionColumnsJob.backfill_allowed?
    return unless select_value('SELECT EXISTS (SELECT 1 FROM point_sources)')

    DataMigrations::BackfillPointCountryIdJob.perform_later(
      nil,
      DataMigrations::BackfillPointCountryIdJob::BATCH_SIZE,
      repair_collisions: true
    )
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.error(
      "[EnqueueCountryCodeCollisionRepair] could not enqueue the repair (#{e.class}: #{e.message}). " \
      'Start it later with: DataMigrations::BackfillPointCountryIdJob.perform_later(' \
      "nil, #{DataMigrations::BackfillPointCountryIdJob::BATCH_SIZE}, repair_collisions: true)"
    )
  end

  def down; end
end

# frozen_string_literal: true

# Existing installs already have `regions` rows, so nothing reloads them when
# the bundled geometry changes: db/seeds.rb only seeds an empty table and
# DataMigrations::BackfillAchievementsJob calls LoadRegions only when codes are
# missing, never when the polygons themselves are corrected. The rebuilt US
# subdivision geometry therefore needs an explicit reload here.
class RefreshUsSubdivisionGeometry < ActiveRecord::Migration[8.1]
  # The re-check reads the reloaded polygons, so it must not be enqueued before
  # the geometry commits: jobs are pushed to Sidekiq immediately here.
  disable_ddl_transaction!

  def up
    return unless table_exists?(:regions)
    return if Country.none? || Region.none?

    transaction { Achievements::LoadRegions.new.call }
    enqueue_recheck
  end

  def down; end

  private

  # Subdivision progress is derived live from `regions` by
  # Achievements::GridDwellCalculator, so no per-point column needs rewriting;
  # the stored Progress rows just need recomputing against the new polygons.
  # notify: false keeps historical earns from blasting alerts.
  def enqueue_recheck
    Achievements::BulkCheckJob.perform_later(notify: false, force: true)
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.error(
      "[RefreshUsSubdivisionGeometry] could not enqueue the achievement re-check (#{e.class}: #{e.message}). " \
      'Start it later with: Achievements::BulkCheckJob.perform_later(notify: false, force: true)'
    )
  end
end

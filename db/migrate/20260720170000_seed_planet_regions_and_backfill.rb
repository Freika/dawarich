# frozen_string_literal: true

class SeedPlanetRegionsAndBackfill < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:regions)

    Region.where.not('code LIKE ?', '%-%').delete_all
    return if Country.none?

    # Reference geometry only; the user backfill is enqueued by the idempotent
    # `rake achievements:backfill` post-deploy task, not from the migration.
    Achievements::LoadRegions.new.call
  end

  def down; end
end

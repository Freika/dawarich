# frozen_string_literal: true

class SeedAchievementRegionsAndBackfill < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:regions)
    return if Country.none?

    # Reference geometry only; the user backfill is enqueued by the idempotent
    # `rake achievements:backfill` post-deploy task, not from the migration.
    Achievements::LoadRegions.new.call if Region.none?
  end

  def down; end
end

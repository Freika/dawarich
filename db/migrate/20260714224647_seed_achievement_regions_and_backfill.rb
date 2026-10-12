# frozen_string_literal: true

class SeedAchievementRegionsAndBackfill < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:regions)
    return if Country.none?

    Achievements::LoadRegions.new.call if Region.none?
  end

  def down; end
end

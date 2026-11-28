# frozen_string_literal: true

class SeedPlanetRegionsAndBackfill < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:regions)

    Region.where.not('code LIKE ?', '%-%').delete_all
    return if Country.none?

    Achievements::LoadRegions.new.call
  end

  def down; end
end

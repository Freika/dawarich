# frozen_string_literal: true

class AddExplorationWorldTotals < ActiveRecord::Migration[8.1]
  def change
    add_column :exploration_datasets, :world_land_area, :float
    add_column :exploration_snapshots, :world_opened_area, :float
  end
end

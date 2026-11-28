# frozen_string_literal: true

class AddExplorationWorldTotals < ActiveRecord::Migration[8.1]
  def up
    add_column :exploration_datasets, :world_land_area, :float, if_not_exists: true
    add_column :exploration_snapshots, :world_opened_area, :float, if_not_exists: true
  end

  def down
    remove_column :exploration_snapshots, :world_opened_area, if_exists: true if table_exists?(:exploration_snapshots)
    remove_column :exploration_datasets, :world_land_area, if_exists: true if table_exists?(:exploration_datasets)
  end
end

# frozen_string_literal: true

class AddAnomalyOverrideToPoints < ActiveRecord::Migration[8.1]
  def up
    add_column :points, :anomaly_override, :boolean, default: false, null: false, if_not_exists: true
  end

  def down
    remove_column :points, :anomaly_override, if_exists: true
  end
end

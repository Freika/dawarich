# frozen_string_literal: true

class AddOutlierToPoints < ActiveRecord::Migration[8.0]
  def change
    add_column :points, :outlier, :boolean, default: false, null: false
    add_index :points, :outlier, where: 'outlier = true', name: 'index_points_on_outlier_true'
  end
end

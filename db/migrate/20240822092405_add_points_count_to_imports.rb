# frozen_string_literal: true

class AddPointsCountToImports < ActiveRecord::Migration[7.1]
  def change
    add_column :imports, :points_count, :integer, default: 0
  end
end

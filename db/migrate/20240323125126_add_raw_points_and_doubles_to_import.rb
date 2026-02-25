# frozen_string_literal: true

class AddRawPointsAndDoublesToImport < ActiveRecord::Migration[7.1]
  def change
    add_column :imports, :raw_points, :integer, default: 0
    add_column :imports, :doubles, :integer, default: 0
  end
end

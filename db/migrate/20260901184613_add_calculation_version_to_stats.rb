# frozen_string_literal: true

class AddCalculationVersionToStats < ActiveRecord::Migration[8.0]
  def change
    add_column :stats, :calculation_version, :integer, default: 0, null: false
  end
end

# frozen_string_literal: true

class AddCalculationVersionToStats < ActiveRecord::Migration[8.0]
  def up
    return if column_exists?(:stats, :calculation_version)

    add_column :stats, :calculation_version, :integer, default: 0, null: false
  end

  def down
    return unless column_exists?(:stats, :calculation_version)

    remove_column :stats, :calculation_version
  end
end

# frozen_string_literal: true

class ChangeStatsDistanceToBigint < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    change_column :stats, :distance, :bigint, null: false, default: 0
  end

  def down
    change_column :stats, :distance, :integer, null: false, default: 0
  end
end

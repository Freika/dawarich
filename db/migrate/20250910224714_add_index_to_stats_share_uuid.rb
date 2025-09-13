# frozen_string_literal: true

class AddIndexToStatsShareUuid < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :stats, :sharing_uuid, unique: true, algorithm: :concurrently
  end
end

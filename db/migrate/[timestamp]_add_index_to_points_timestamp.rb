# frozen_string_literal: true

class AddIndexToPointsTimestamp < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :points, %i[user_id timestamp], algorithm: :concurrently
  end
end

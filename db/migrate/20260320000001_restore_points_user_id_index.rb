# frozen_string_literal: true

class RestorePointsUserIdIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :points, :user_id, algorithm: :concurrently, if_not_exists: true
  end
end

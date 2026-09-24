# frozen_string_literal: true

class AddUserIdCreatedAtIndexToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :points, %i[user_id created_at], algorithm: :concurrently, if_not_exists: true
  end
end

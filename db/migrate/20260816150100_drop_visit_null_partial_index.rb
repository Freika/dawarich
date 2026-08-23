# frozen_string_literal: true

class DropVisitNullPartialIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :points, name: 'idx_points_user_visit_null_timestamp',
                          algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :points, %i[user_id timestamp],
              where: 'visit_id IS NULL',
              name: 'idx_points_user_visit_null_timestamp',
              algorithm: :concurrently,
              if_not_exists: true
  end
end

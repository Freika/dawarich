# frozen_string_literal: true

class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Query: SELECT * FROM users WHERE api_key = $1
    add_index :users, :api_key,
              algorithm: :concurrently,
              if_not_exists: true

    # Query: SELECT id FROM users WHERE status = $1
    add_index :users, :status,
              algorithm: :concurrently,
              if_not_exists: true

    # Query: SELECT DISTINCT city FROM points WHERE user_id = $1 AND city IS NOT NULL
    add_index :points, %i[user_id city],
              name: 'idx_points_user_city',
              algorithm: :concurrently,
              if_not_exists: true

    # Query: SELECT 1 FROM points WHERE user_id = $1 AND visit_id IS NULL AND timestamp BETWEEN...
    add_index :points, %i[user_id timestamp],
              name: 'idx_points_user_visit_null_timestamp',
              where: 'visit_id IS NULL',
              algorithm: :concurrently,
              if_not_exists: true
  end
end

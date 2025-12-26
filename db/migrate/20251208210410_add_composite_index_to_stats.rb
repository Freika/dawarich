# frozen_string_literal: true

class AddCompositeIndexToStats < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Add composite index for the most common stats lookup pattern:
    # Stat.find_or_initialize_by(year:, month:, user:)
    # This query is called on EVERY stats calculation
    #
    # Using algorithm: :concurrently to avoid locking the table during index creation
    # This is crucial for production deployments with existing data
    add_index :stats, %i[user_id year month],
              name: 'index_stats_on_user_id_year_month',
              unique: true,
              algorithm: :concurrently
  end
end

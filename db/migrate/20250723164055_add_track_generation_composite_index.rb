# frozen_string_literal: true

class AddTrackGenerationCompositeIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :points, %i[user_id timestamp track_id],
              algorithm: :concurrently,
              name: 'idx_points_track_generation', if_not_exists: true
  end
end

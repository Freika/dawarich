# frozen_string_literal: true

class AddExternalTrackIdToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :points, :external_track_id, :string

    add_index :points, :external_track_id, algorithm: :concurrently
  end
end

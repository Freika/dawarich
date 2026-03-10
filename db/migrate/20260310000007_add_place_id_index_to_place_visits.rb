# frozen_string_literal: true

class AddPlaceIdIndexToPlaceVisits < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Place has `has_many :place_visits, dependent: :destroy`, which generates
    # DELETE FROM place_visits WHERE place_id = ?. Without a single-column
    # place_id index this becomes a sequential scan. The composite
    # (visit_id, place_id) index from migration 3 does not cover this
    # because place_id is not the leading column.
    add_index :place_visits, :place_id,
              name: :index_place_visits_on_place_id,
              algorithm: :concurrently,
              if_not_exists: true
  end
end

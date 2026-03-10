# frozen_string_literal: true

class AddUniqueIndexToPlaceVisits < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Remove duplicate (visit_id, place_id) rows, keeping the oldest
    execute <<~SQL.squish
      DELETE FROM place_visits
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM place_visits
        GROUP BY visit_id, place_id
      )
    SQL

    # Add unique composite index, replacing both single-column indexes
    add_index :place_visits, %i[visit_id place_id],
              name: :idx_place_visits_visit_id_place_id,
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true

    remove_index :place_visits, column: :visit_id,
                 name: :index_place_visits_on_visit_id,
                 algorithm: :concurrently,
                 if_exists: true

    remove_index :place_visits, column: :place_id,
                 name: :index_place_visits_on_place_id,
                 algorithm: :concurrently,
                 if_exists: true
  end

  def down
    add_index :place_visits, :visit_id,
              name: :index_place_visits_on_visit_id,
              algorithm: :concurrently,
              if_not_exists: true

    add_index :place_visits, :place_id,
              name: :index_place_visits_on_place_id,
              algorithm: :concurrently,
              if_not_exists: true

    remove_index :place_visits, name: :idx_place_visits_visit_id_place_id,
                 algorithm: :concurrently,
                 if_exists: true
  end
end

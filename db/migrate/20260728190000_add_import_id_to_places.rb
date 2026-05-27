# frozen_string_literal: true

class AddImportIdToPlaces < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :places, :import_id, :bigint unless column_exists?(:places, :import_id)

    unless index_exists?(:places, :import_id, name: 'index_places_on_import_id')
      # Every place predating this column is NULL, and nothing looks those up
      # by import, so they stay out of the index.
      add_index :places, :import_id,
                where: 'import_id IS NOT NULL',
                name: 'index_places_on_import_id',
                algorithm: :concurrently
    end

    return if index_exists?(:places, %i[user_id name latitude longitude], name: 'index_imported_places_uniqueness')

    # Scoped to the two import sources, which no existing row can carry, so the
    # index cannot conflict with places created by geocoding or by hand.
    add_index :places, %i[user_id name latitude longitude],
              unique: true,
              where: 'source IN (2, 3)',
              name: 'index_imported_places_uniqueness',
              algorithm: :concurrently
  end

  def down
    remove_index :places, name: 'index_imported_places_uniqueness' if
      index_exists?(:places, %i[user_id name latitude longitude], name: 'index_imported_places_uniqueness')
    remove_index :places, name: 'index_places_on_import_id' if
      index_exists?(:places, :import_id, name: 'index_places_on_import_id')
    remove_column :places, :import_id if column_exists?(:places, :import_id)
  end
end

class AddIndexOnPlacesGeodataOsmId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :places, "(geodata->'properties'->>'osm_id')", 
              using: :btree, 
              name: 'index_places_on_geodata_osm_id',
              algorithm: :concurrently
  end
end

# frozen_string_literal: true

class CreateRegions < ActiveRecord::Migration[8.0]
  def up
    return if table_exists?(:regions)

    create_table :regions do |t|
      t.string :code, null: false
      t.multi_polygon :geom, srid: 4326, null: false
      t.timestamps
    end

    add_index :regions, :code, unique: true
    add_index :regions, :geom, using: :gist
  end

  def down
    drop_table :regions, if_exists: true
  end
end

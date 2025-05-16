class CreateCountries < ActiveRecord::Migration[8.0]
  def change
    create_table :countries do |t|
      t.string :name, null: false
      t.string :iso_a2, null: false
      t.string :iso_a3, null: false
      t.multi_polygon :geom, srid: 4326

      t.timestamps
    end

    add_index :countries, :name
    add_index :countries, :iso_a2
    add_index :countries, :iso_a3
    add_index :countries, :geom, using: :gist
  end
end

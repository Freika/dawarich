class CreateRoutePresets < ActiveRecord::Migration[8.0]
  def change
    create_table :route_presets do |t|
      t.string :name, null: false
      t.float :start_lat
      t.float :start_lng
      t.float :end_lat
      t.float :end_lng
      t.jsonb :via_points, null: false, default: []

      t.timestamps
    end

    add_index :route_presets, :name, unique: true
  end
end

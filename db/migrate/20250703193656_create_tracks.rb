class CreateTracks < ActiveRecord::Migration[8.0]
  def change
    create_table :tracks do |t|
      t.datetime :start_at, null: false
      t.datetime :end_at, null: false
      t.references :user, null: false, foreign_key: true
      t.line_string :original_path, null: false
      t.decimal :distance, precision: 8, scale: 2
      t.float :avg_speed
      t.integer :duration
      t.integer :elevation_gain
      t.integer :elevation_loss
      t.integer :elevation_max
      t.integer :elevation_min

      t.timestamps
    end
  end
end

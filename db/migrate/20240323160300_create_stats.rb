class CreateStats < ActiveRecord::Migration[7.1]
  def change
    create_table :stats do |t|
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :distance, null: false
      t.jsonb :toponyms

      t.timestamps
    end
    add_index :stats, :year
    add_index :stats, :month
    add_index :stats, :distance
  end
end

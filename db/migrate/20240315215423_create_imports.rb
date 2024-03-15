class CreateImports < ActiveRecord::Migration[7.1]
  def change
    create_table :imports do |t|
      t.string :name, null: false
      t.bigint :user_id, null: false
      t.integer :source, default: 0

      t.timestamps
    end
    add_index :imports, :user_id
    add_index :imports, :source
  end
end

# frozen_string_literal: true

class CreateExports < ActiveRecord::Migration[7.1]
  def change
    create_table :exports do |t|
      t.string :name, null: false
      t.string :url
      t.integer :status, default: 0, null: false
      t.bigint :user_id, null: false

      t.timestamps
    end
    add_index :exports, :status
    add_index :exports, :user_id
  end
end

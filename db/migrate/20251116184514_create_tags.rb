# frozen_string_literal: true

class CreateTags < ActiveRecord::Migration[8.0]
  def change
    create_table :tags do |t|
      t.string :name, null: false
      t.string :icon
      t.string :color
      t.references :user, null: false, foreign_key: true, index: true

      t.timestamps
    end

    add_index :tags, %i[user_id name], unique: true
  end
end

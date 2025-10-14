# frozen_string_literal: true

class CreateFamilies < ActiveRecord::Migration[8.0]
  def change
    create_table :families do |t|
      t.string :name, null: false, limit: 50
      t.bigint :creator_id, null: false
      t.timestamps
    end

    add_foreign_key :families, :users, column: :creator_id, validate: false
    add_index :families, :creator_id
  end
end

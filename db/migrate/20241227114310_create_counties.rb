# frozen_string_literal: true

class CreateCounties < ActiveRecord::Migration[8.0]
  def change
    create_table :counties do |t|
      t.string :name
      t.references :country, null: false, foreign_key: true
      t.references :state, foreign_key: true

      t.timestamps
    end
  end
end

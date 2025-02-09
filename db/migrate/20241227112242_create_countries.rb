# frozen_string_literal: true

class CreateCountries < ActiveRecord::Migration[8.0]
  def change
    create_table :countries do |t|
      t.string :name, null: false
      t.string :iso2_code, null: false

      t.timestamps
    end

    add_index :countries, :name
    add_index :countries, :iso2_code
  end
end

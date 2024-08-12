# frozen_string_literal: true

class CreatePlaceVisits < ActiveRecord::Migration[7.1]
  def change
    create_table :place_visits do |t|
      t.references :place, null: false, foreign_key: true
      t.references :visit, null: false, foreign_key: true

      t.timestamps
    end
  end
end

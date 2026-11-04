# frozen_string_literal: true

class CreateTimezones < ActiveRecord::Migration[8.1]
  def up
    create_table :timezones, if_not_exists: true do |t|
      t.string :tzid, null: false
      t.geometry :geom, srid: 4326, null: false

      t.timestamps
    end

    add_index :timezones, :geom, using: :gist, if_not_exists: true
  end

  # Dropping the table drops its index with it.
  def down
    drop_table :timezones, if_exists: true
  end
end

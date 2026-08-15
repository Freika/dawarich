# frozen_string_literal: true

class CreateFlights < ActiveRecord::Migration[8.0]
  def change
    create_table :flights, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.integer :external_id, null: false
      t.date :flight_date
      t.string :date_precision, default: 'day', null: false
      t.datetime :departure_time
      t.datetime :arrival_time
      t.string :from_code
      t.string :from_name
      t.float :from_lat
      t.float :from_lon
      t.string :to_code
      t.string :to_name
      t.float :to_lat
      t.float :to_lon
      t.string :airline_name
      t.string :airline_iata
      t.string :aircraft_name
      t.string :aircraft_reg
      t.string :flight_number
      t.string :seat
      t.string :seat_class
      t.text :note
      t.float :distance_km
      t.jsonb :raw, default: {}, null: false

      t.timestamps
    end

    add_index :flights, %i[user_id external_id], unique: true, if_not_exists: true
    add_index :flights, %i[user_id departure_time], if_not_exists: true
  end
end

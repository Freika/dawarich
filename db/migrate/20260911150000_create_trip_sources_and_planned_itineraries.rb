# frozen_string_literal: true

class CreateTripSourcesAndPlannedItineraries < ActiveRecord::Migration[8.0]
  def change
    create_table :trip_sources do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :base_url, null: false
      t.text :api_key
      t.integer :status, null: false, default: 0
      t.datetime :last_synced_at
      t.text :last_error
      t.timestamps
    end

    add_index :trip_sources, %i[user_id provider base_url], unique: true

    change_table :trips, bulk: true do |t|
      t.references :trip_source, foreign_key: true
      t.string :source_identifier
      t.integer :source_status
      t.string :source_digest
      t.datetime :source_synced_at
      t.jsonb :source_snapshot, null: false, default: {}
    end

    add_index :trips, %i[trip_source_id source_identifier], unique: true,
              where: 'trip_source_id IS NOT NULL AND source_identifier IS NOT NULL',
              name: 'index_trips_on_source_identifier'

    create_table :planned_days do |t|
      t.references :trip, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :position, null: false
      t.string :title
      t.text :notes
      t.timestamps
    end
    add_index :planned_days, %i[trip_id date], unique: true

    create_table :planned_stops do |t|
      t.references :planned_day, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :name, null: false
      t.string :address
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.time :starts_at
      t.time :ends_at
      t.integer :duration_minutes
      t.string :category
      t.string :transport_mode
      t.text :notes
      t.timestamps
    end
    add_index :planned_stops, %i[planned_day_id position], unique: true

    create_table :planned_day_notes do |t|
      t.references :planned_day, null: false, foreign_key: true
      t.integer :position, null: false
      t.time :noted_at
      t.text :body, null: false
      t.timestamps
    end
    add_index :planned_day_notes, %i[planned_day_id position], unique: true

    create_table :planned_reservations do |t|
      t.references :trip, null: false, foreign_key: true
      t.references :planned_day, foreign_key: true
      t.string :reservation_type
      t.string :title, null: false
      t.string :location
      t.datetime :starts_at
      t.datetime :ends_at
      t.string :status
      t.text :notes
      t.timestamps
    end

    create_table :planned_accommodations do |t|
      t.references :trip, null: false, foreign_key: true
      t.string :name, null: false
      t.string :address
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.date :starts_on
      t.date :ends_on
      t.time :check_in_at
      t.time :check_out_at
      t.text :notes
      t.timestamps
    end

    create_table :planned_travellers do |t|
      t.references :trip, null: false, foreign_key: true
      t.string :name, null: false
      t.boolean :owner, null: false, default: false
      t.timestamps
    end
  end
end

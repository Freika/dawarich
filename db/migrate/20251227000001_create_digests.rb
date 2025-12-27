# frozen_string_literal: true

class CreateDigests < ActiveRecord::Migration[8.0]
  def change
    create_table :digests do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :year, null: false
      t.integer :period_type, null: false, default: 0 # enum: monthly: 0, yearly: 1

      # Aggregated data
      t.bigint :distance, null: false, default: 0 # Total distance in meters
      t.jsonb :toponyms, default: {}               # Countries/cities data
      t.jsonb :monthly_distances, default: {}      # {1: meters, 2: meters, ...}
      t.jsonb :time_spent_by_location, default: {} # Top locations by time

      # First-time visits (calculated from historical data)
      t.jsonb :first_time_visits, default: {} # {countries: [], cities: []}

      # Comparisons
      t.jsonb :year_over_year, default: {} # {distance_change_percent: 15, ...}
      t.jsonb :all_time_stats, default: {} # {total_countries: 50, ...}

      # Sharing (like Stat model)
      t.jsonb :sharing_settings, default: {}
      t.uuid :sharing_uuid

      # Email tracking
      t.datetime :sent_at

      t.timestamps
    end

    add_index :digests, %i[user_id year period_type], unique: true
    add_index :digests, :sharing_uuid, unique: true
    add_index :digests, :year
    add_index :digests, :period_type
  end
end

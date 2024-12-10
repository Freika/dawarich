# frozen_string_literal: true

class AddReverseGeocodedAtToPoints < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_column :points, :reverse_geocoded_at, :datetime

    add_index :points, :reverse_geocoded_at, algorithm: :concurrently
  end
end

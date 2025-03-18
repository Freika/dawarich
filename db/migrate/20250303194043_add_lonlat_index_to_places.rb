# frozen_string_literal: true

class AddLonlatIndexToPlaces < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :places, :lonlat, using: :gist, algorithm: :concurrently
  end
end

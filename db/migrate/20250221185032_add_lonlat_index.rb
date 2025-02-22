# frozen_string_literal: true

class AddLonlatIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :points, :lonlat, using: :gist, algorithm: :concurrently
  end
end

# frozen_string_literal: true

class AddSharingToTrips < ActiveRecord::Migration[8.0]
  def change
    add_column :trips, :sharing_uuid, :uuid
    add_column :trips, :sharing_settings, :jsonb, default: {}
    add_index :trips, :sharing_uuid, unique: true
  end
end

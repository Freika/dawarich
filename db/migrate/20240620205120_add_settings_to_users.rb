# frozen_string_literal: true

class AddSettingsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :settings, :jsonb, default: {
      meters_between_routes: 500,
      minutes_between_routes: 60
    }
  end
end

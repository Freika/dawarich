# frozen_string_literal: true

class AddImportingToTripSources < ActiveRecord::Migration[8.0]
  def change
    add_column :trip_sources, :importing, :boolean, null: false, default: false
  end
end

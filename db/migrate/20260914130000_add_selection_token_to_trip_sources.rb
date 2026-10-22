# frozen_string_literal: true

class AddSelectionTokenToTripSources < ActiveRecord::Migration[8.0]
  def change
    add_column :trip_sources, :selection_token, :string
  end
end

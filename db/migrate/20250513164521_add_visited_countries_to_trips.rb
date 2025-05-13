# frozen_string_literal: true

class AddVisitedCountriesToTrips < ActiveRecord::Migration[8.0]
  def change
    add_column :trips, :visited_countries, :jsonb, default: []
  end
end

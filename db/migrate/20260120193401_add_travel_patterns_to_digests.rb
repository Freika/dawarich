# frozen_string_literal: true

class AddTravelPatternsToDigests < ActiveRecord::Migration[8.0]
  def change
    add_column :digests, :travel_patterns, :jsonb, default: {}, if_not_exists: true
  end
end

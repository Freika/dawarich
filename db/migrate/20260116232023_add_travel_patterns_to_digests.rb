class AddTravelPatternsToDigests < ActiveRecord::Migration[8.0]
  def change
    add_column :digests, :travel_patterns, :jsonb, default: {}
  end
end

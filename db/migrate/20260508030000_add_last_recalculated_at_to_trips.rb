# frozen_string_literal: true

class AddLastRecalculatedAtToTrips < ActiveRecord::Migration[8.0]
  def change
    add_column :trips, :last_recalculated_at, :datetime
  end
end

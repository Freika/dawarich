# frozen_string_literal: true

class AddVisitsScannedAtToPoints < ActiveRecord::Migration[8.0]
  def change
    return if column_exists?(:points, :visits_scanned_at)

    add_column :points, :visits_scanned_at, :datetime
  end
end

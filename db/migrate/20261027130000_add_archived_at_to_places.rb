# frozen_string_literal: true

class AddArchivedAtToPlaces < ActiveRecord::Migration[8.1]
  def change
    add_column :places, :archived_at, :datetime
  end
end

# frozen_string_literal: true

class AddArchivedAtToPlaces < ActiveRecord::Migration[8.1]
  def up
    add_column :places, :archived_at, :datetime, if_not_exists: true
  end

  def down
    remove_column :places, :archived_at, if_exists: true
  end
end

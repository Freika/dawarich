# frozen_string_literal: true

class AddPointsArchiveStateToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :points_archive_state, :integer, default: 0, null: false
    add_column :users, :points_archived_at, :datetime
    add_index :users, :points_archive_state
  end
end

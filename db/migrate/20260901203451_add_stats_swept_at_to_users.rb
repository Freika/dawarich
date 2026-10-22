# frozen_string_literal: true

class AddStatsSweptAtToUsers < ActiveRecord::Migration[8.0]
  def up
    return if column_exists?(:users, :stats_swept_at)

    add_column :users, :stats_swept_at, :datetime
  end

  def down
    return unless column_exists?(:users, :stats_swept_at)

    remove_column :users, :stats_swept_at
  end
end

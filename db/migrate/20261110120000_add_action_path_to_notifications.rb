# frozen_string_literal: true

# Where a notification leads when it is opened: a local path such as /exports.
class AddActionPathToNotifications < ActiveRecord::Migration[8.1]
  def up
    add_column :notifications, :action_path, :string, if_not_exists: true
  end

  def down
    remove_column :notifications, :action_path, if_exists: true
  end
end

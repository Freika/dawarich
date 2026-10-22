# frozen_string_literal: true

class AddNameLockedAtToPlaces < ActiveRecord::Migration[8.0]
  def change
    return if column_exists?(:places, :name_locked_at)

    add_column :places, :name_locked_at, :datetime
  end
end

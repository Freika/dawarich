# frozen_string_literal: true

# The time a Place was part of the user's life. Both dates are optional; an empty one is an open end.
class AddPeriodToPlaces < ActiveRecord::Migration[8.1]
  def up
    add_column :places, :started_on, :date, if_not_exists: true
    add_column :places, :ended_on, :date, if_not_exists: true
  end

  def down
    remove_column :places, :ended_on, if_exists: true
    remove_column :places, :started_on, if_exists: true
  end
end

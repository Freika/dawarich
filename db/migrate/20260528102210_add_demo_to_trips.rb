# frozen_string_literal: true

class AddDemoToTrips < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :trips, :demo, :boolean, default: false, null: false, if_not_exists: true
    add_index  :trips, :demo,
               where: 'demo = true',
               name: 'index_trips_on_demo_true',
               algorithm: :concurrently,
               if_not_exists: true
  end

  def down
    remove_index  :trips, name: 'index_trips_on_demo_true', if_exists: true
    remove_column :trips, :demo, if_exists: true
  end
end

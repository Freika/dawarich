# frozen_string_literal: true

class AddDemoToPlaces < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :places, :demo, :boolean, default: false, null: false, if_not_exists: true
    add_index  :places, :demo,
               where: 'demo = true',
               name: 'index_places_on_demo_true',
               algorithm: :concurrently,
               if_not_exists: true
  end

  def down
    remove_index  :places, name: 'index_places_on_demo_true', if_exists: true
    remove_column :places, :demo, if_exists: true
  end
end

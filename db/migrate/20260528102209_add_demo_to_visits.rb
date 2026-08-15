# frozen_string_literal: true

class AddDemoToVisits < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :visits, :demo, :boolean, default: false, null: false, if_not_exists: true
    add_index  :visits, :demo,
               where: 'demo = true',
               name: 'index_visits_on_demo_true',
               algorithm: :concurrently,
               if_not_exists: true
  end

  def down
    remove_index  :visits, name: 'index_visits_on_demo_true', if_exists: true
    remove_column :visits, :demo, if_exists: true
  end
end

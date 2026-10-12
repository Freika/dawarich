# frozen_string_literal: true

class AddDemoToTags < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :tags, :demo, :boolean, default: false, null: false, if_not_exists: true
    add_index  :tags, :demo,
               where: 'demo = true',
               name: 'index_tags_on_demo_true',
               algorithm: :concurrently,
               if_not_exists: true
  end

  def down
    remove_index  :tags, name: 'index_tags_on_demo_true', if_exists: true
    remove_column :tags, :demo, if_exists: true
  end
end

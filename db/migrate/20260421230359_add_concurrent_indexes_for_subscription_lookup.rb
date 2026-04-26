# frozen_string_literal: true

class AddConcurrentIndexesForSubscriptionLookup < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_users_on_subscription_source'

  def up
    return if index_name_exists?(:users, INDEX_NAME)

    add_index :users, :subscription_source,
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    return unless index_name_exists?(:users, INDEX_NAME)

    remove_index :users, name: INDEX_NAME, algorithm: :concurrently
  end
end

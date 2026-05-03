# frozen_string_literal: true

class DropRedundantUsersProviderUidIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  LEGACY_INDEX = 'index_users_on_provider_and_uid'

  def up
    return unless index_name_exists?(:users, LEGACY_INDEX)

    remove_index :users, name: LEGACY_INDEX, algorithm: :concurrently
  end

  def down
    return if index_name_exists?(:users, LEGACY_INDEX)

    add_index :users, %i[provider uid], unique: true, algorithm: :concurrently, name: LEGACY_INDEX
  end
end

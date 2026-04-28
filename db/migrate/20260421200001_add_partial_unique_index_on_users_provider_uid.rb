# frozen_string_literal: true

class AddPartialUniqueIndexOnUsersProviderUid < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_users_on_provider_and_uid_present'

  def up
    # The existing `index_users_on_provider_and_uid` index is unique across ALL rows
    # (including NULL provider/uid rows, which PostgreSQL treats as distinct NULLs —
    # so uniqueness is effectively not enforced for rows without OAuth).
    # Replace it with a partial unique index that only covers rows where both
    # provider and uid are present, making the semantic intent explicit and
    # avoiding the edge case where NULL,NULL rows slip through.
    return if index_name_exists?(:users, INDEX_NAME)

    add_index :users, %i[provider uid],
              unique: true,
              where: 'provider IS NOT NULL AND uid IS NOT NULL',
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    return unless index_name_exists?(:users, INDEX_NAME)

    remove_index :users, name: INDEX_NAME, algorithm: :concurrently
  end
end

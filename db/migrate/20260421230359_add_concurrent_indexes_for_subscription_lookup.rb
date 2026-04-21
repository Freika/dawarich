# frozen_string_literal: true

# Re-add `index_users_on_subscription_source` using CONCURRENTLY so the index
# is safe to apply on the production users table without blocking writes.
#
# The original migration (20260420190307_add_subscription_source_and_signup_variant_to_users)
# created this index non-concurrently inside `def change`. That's fine on a
# fresh schema load (schema.rb never honors :algorithm anyway), but we want a
# recorded, idempotent, concurrent path for any environment where the column
# exists without the index, or where the previous migration was skipped.
#
# Coordinated with the user-model agent:
#   - 20260421200001_add_partial_unique_index_on_users_provider_uid  owns the
#     partial unique provider/uid index (name: ..._present).
#   - 20260421200002_add_partial_index_on_users_signup_variant_reverse_trial
#     owns the partial signup_variant index.
# Those are not re-done here to avoid duplicate indexes.
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
    # Do not drop on rollback — the original migration 20260420190307 created
    # this index and the app relies on it.
  end
end

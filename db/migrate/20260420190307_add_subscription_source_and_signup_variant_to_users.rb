# frozen_string_literal: true

# Idempotent column additions for the subscription/signup_variant rollout.
#
# The `subscription_source` index is intentionally *not* added here — migration
# 20260421230359_add_concurrent_indexes_for_subscription_lookup creates it
# CONCURRENTLY so it's safe on large `users` tables.
#
# Rollback ordering: the `down` method MUST drop dependent indexes before the
# columns. Two later migrations attach indexes to these columns:
#   * 20260421200002 — partial index `index_users_on_signup_variant_reverse_trial`
#     on `signup_variant`
#   * 20260421230359 — index `index_users_on_subscription_source` on
#     `subscription_source`
# Postgres refuses `DROP COLUMN` while an index references the column, so we
# remove indexes first. Each removal is guarded by `index_name_exists?` /
# `column_exists?` so the migration is idempotent on partial-rollback states.
class AddSubscriptionSourceAndSignupVariantToUsers < ActiveRecord::Migration[8.0]
  SIGNUP_VARIANT_INDEX = 'index_users_on_signup_variant_reverse_trial'
  SUBSCRIPTION_SOURCE_INDEX = 'index_users_on_subscription_source'

  def up
    unless column_exists?(:users, :subscription_source)
      add_column :users, :subscription_source, :integer, default: 0, null: false
    end

    return if column_exists?(:users, :signup_variant)

    add_column :users, :signup_variant, :string
  end

  def down
    # Drop indexes BEFORE columns — Postgres rejects `DROP COLUMN` on an
    # indexed column. Each index is owned by a later migration but we must
    # tolerate its presence here so this migration can be rolled all the way
    # back without manual cleanup.
    remove_index :users, name: SIGNUP_VARIANT_INDEX if index_name_exists?(:users, SIGNUP_VARIANT_INDEX)
    remove_index :users, name: SUBSCRIPTION_SOURCE_INDEX if index_name_exists?(:users, SUBSCRIPTION_SOURCE_INDEX)

    remove_column :users, :signup_variant if column_exists?(:users, :signup_variant)
    remove_column :users, :subscription_source if column_exists?(:users, :subscription_source)
  end
end

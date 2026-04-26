# frozen_string_literal: true

# Idempotent column additions for the subscription/signup_variant rollout.
#
# The `subscription_source` index is intentionally *not* added here — migration
# 20260421230359_add_concurrent_indexes_for_subscription_lookup creates it
# CONCURRENTLY so it's safe on large `users` tables. Likewise, the partial
# index on `signup_variant` is owned by 20260421200002.
#
# Rollback ordering: this migration only undoes the column additions it
# performed. Roll back later migrations first — they own their own indexes
# and will drop them in their own `down`. Postgres rejects `DROP COLUMN` on
# an indexed column, so calling `down` here while a later migration's index
# is still present will (correctly) fail and signal the wrong rollback order.
class AddSubscriptionSourceAndSignupVariantToUsers < ActiveRecord::Migration[8.0]
  def up
    unless column_exists?(:users, :subscription_source)
      add_column :users, :subscription_source, :integer, default: 0, null: false
    end

    return if column_exists?(:users, :signup_variant)

    add_column :users, :signup_variant, :string
  end

  def down
    remove_column :users, :signup_variant if column_exists?(:users, :signup_variant)
    remove_column :users, :subscription_source if column_exists?(:users, :subscription_source)
  end
end

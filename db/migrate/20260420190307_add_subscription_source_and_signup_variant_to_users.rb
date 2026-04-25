# frozen_string_literal: true

# Adds the `subscription_source` column for tracking where a user's
# subscription originates (Paddle, Apple IAP, Google Play, or none).
#
# NOTE (PR-A — mobile auth scope): The `signup_variant` column originally added
# in this migration was deferred to the reverse-trial PR. This migration now
# adds only `subscription_source`. The migration filename retains the original
# `_signup_variant_` suffix to preserve the migration version sequence.
#
# A future migration in the reverse-trial PR will add `signup_variant` (string)
# and any partial indexes that depend on it.
class AddSubscriptionSourceAndSignupVariantToUsers < ActiveRecord::Migration[8.0]
  SUBSCRIPTION_SOURCE_INDEX = 'index_users_on_subscription_source'

  def up
    return if column_exists?(:users, :subscription_source)

    add_column :users, :subscription_source, :integer, default: 0, null: false
  end

  def down
    # Drop dependent indexes BEFORE the column — Postgres rejects `DROP COLUMN`
    # on an indexed column. The subscription_source index is owned by a later
    # migration but we tolerate its presence here so this migration can be
    # rolled back without manual cleanup.
    remove_index :users, name: SUBSCRIPTION_SOURCE_INDEX if index_name_exists?(:users, SUBSCRIPTION_SOURCE_INDEX)

    remove_column :users, :subscription_source if column_exists?(:users, :subscription_source)
  end
end

# frozen_string_literal: true

# Adds `subscription_source` (where the user's subscription originates —
# Paddle, Apple IAP, Google Play, or none) and `signup_variant` (reverse-trial
# A/B bucketing) to the users table.
class AddSubscriptionSourceAndSignupVariantToUsers < ActiveRecord::Migration[8.0]
  SUBSCRIPTION_SOURCE_INDEX = 'index_users_on_subscription_source'

  def up
    unless column_exists?(:users, :subscription_source)
      add_column :users, :subscription_source, :integer, default: 0, null: false
    end

    return if column_exists?(:users, :signup_variant)

    add_column :users, :signup_variant, :string
  end

  def down
    # Drop dependent indexes BEFORE the columns — Postgres rejects `DROP COLUMN`
    # on an indexed column unless the index is dropped first (CASCADE would also
    # remove the partial index on signup_variant, but doing it explicitly is safer).
    remove_index :users, name: SUBSCRIPTION_SOURCE_INDEX if index_name_exists?(:users, SUBSCRIPTION_SOURCE_INDEX)

    remove_column :users, :signup_variant if column_exists?(:users, :signup_variant)
    remove_column :users, :subscription_source if column_exists?(:users, :subscription_source)
  end
end

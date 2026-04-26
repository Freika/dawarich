# frozen_string_literal: true

class AddSubscriptionSourceAndSignupVariantToUsers < ActiveRecord::Migration[8.0]
  def up
    unless column_exists?(:users, :subscription_source)
      add_column :users, :subscription_source, :integer, default: 0, null: false
    end

    return if column_exists?(:users, :signup_variant)

    add_column :users, :signup_variant, :string
  end

  def down
    # Roll back 20260421200002 first; otherwise PostgreSQL CASCADE-drops the partial index on signup_variant.
    remove_column :users, :signup_variant if column_exists?(:users, :signup_variant)
    remove_column :users, :subscription_source if column_exists?(:users, :subscription_source)
  end
end

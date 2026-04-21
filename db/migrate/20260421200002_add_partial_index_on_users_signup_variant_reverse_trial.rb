# frozen_string_literal: true

class AddPartialIndexOnUsersSignupVariantReverseTrial < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_users_on_signup_variant_reverse_trial'

  def up
    return if index_name_exists?(:users, INDEX_NAME)

    # The PendingPaymentPurgeJob and PendingPaymentReminderJob both query
    #   WHERE status = 'pending_payment' AND signup_variant = 'reverse_trial'.
    # A partial index keyed on only the relevant variant is much smaller than
    # a full index over all signup_variant values.
    add_index :users, :signup_variant,
              where: "signup_variant = 'reverse_trial'",
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    return unless index_name_exists?(:users, INDEX_NAME)

    remove_index :users, name: INDEX_NAME, algorithm: :concurrently
  end
end

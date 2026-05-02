# frozen_string_literal: true

class AddFailedOtpAttemptsToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = 'index_users_on_otp_locked_at_not_null'

  def up
    add_column :users, :failed_otp_attempts, :integer, default: 0, null: false unless column_exists?(:users, :failed_otp_attempts)
    add_column :users, :otp_locked_at, :datetime unless column_exists?(:users, :otp_locked_at)

    return if index_name_exists?(:users, INDEX_NAME)

    add_index :users, :otp_locked_at,
              where: 'otp_locked_at IS NOT NULL',
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    remove_index :users, name: INDEX_NAME, algorithm: :concurrently if index_name_exists?(:users, INDEX_NAME)
    remove_column :users, :otp_locked_at if column_exists?(:users, :otp_locked_at)
    remove_column :users, :failed_otp_attempts if column_exists?(:users, :failed_otp_attempts)
  end
end

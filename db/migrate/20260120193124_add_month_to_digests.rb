# frozen_string_literal: true

class AddMonthToDigests < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :digests, :month, :integer, if_not_exists: true

    remove_index :digests, %i[user_id year period_type], if_exists: true

    # Add new unique index that handles both yearly (month=null) and monthly
    add_index :digests, %i[user_id year month period_type],
              unique: true,
              name: 'index_digests_on_user_year_month_period_type',
              algorithm: :concurrently,
              if_not_exists: true
  end
end

# frozen_string_literal: true

class AddMonthToDigests < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :digests, :month, :integer

    # Remove old unique index (safety_assured since we're replacing with a better index)
    safety_assured { remove_index :digests, %i[user_id year period_type] }

    # Add new unique index that handles both yearly (month=null) and monthly
    add_index :digests, %i[user_id year month period_type],
              unique: true,
              name: 'index_digests_on_user_year_month_period_type',
              algorithm: :concurrently,
              if_not_exists: true
  end
end

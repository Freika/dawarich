# frozen_string_literal: true

class AddUserCountryCompositeIndexToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :points, %i[user_id country_name],
              algorithm: :concurrently,
              name: 'idx_points_user_country_name',
              if_not_exists: true
  end
end

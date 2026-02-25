# frozen_string_literal: true

class AddUserIdReverseGeocodedAtIndexToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :points,
              %i[user_id reverse_geocoded_at],
              where: 'reverse_geocoded_at IS NOT NULL',
              algorithm: :concurrently,
              name: 'index_points_on_user_id_and_reverse_geocoded_at',
              if_not_exists: true
  end
end

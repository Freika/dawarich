# frozen_string_literal: true

class AddPlacesUserIdNotNullCheck < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :places, 'user_id IS NOT NULL', name: 'places_user_id_not_null', validate: false
  end
end

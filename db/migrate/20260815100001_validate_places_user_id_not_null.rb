# frozen_string_literal: true

class ValidatePlacesUserIdNotNull < ActiveRecord::Migration[8.0]
  def up
    validate_check_constraint :places, name: 'places_user_id_not_null'
    change_column_null :places, :user_id, false
    remove_check_constraint :places, name: 'places_user_id_not_null'
  end

  def down
    add_check_constraint :places, 'user_id IS NOT NULL', name: 'places_user_id_not_null', validate: false
    change_column_null :places, :user_id, true
  end
end

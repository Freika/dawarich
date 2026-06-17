# frozen_string_literal: true

class ValidateNullLonlatPointsConstraint < ActiveRecord::Migration[8.0]
  CONSTRAINT_NAME = 'points_lonlat_null'

  def up
    validate_check_constraint :points, name: CONSTRAINT_NAME
    change_column_null :points, :lonlat, false
    remove_check_constraint :points, name: CONSTRAINT_NAME
  end

  def down
    change_column_null :points, :lonlat, true
    add_check_constraint :points, 'lonlat IS NOT NULL', name: CONSTRAINT_NAME, validate: false
  end
end

# frozen_string_literal: true

class ValidatePlaceVisitRadiusConstraint < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  VISIT_RADIUS_CONSTRAINT = 'places_visit_radius_positive'

  def up
    return unless check_constraint_exists?(:places, name: VISIT_RADIUS_CONSTRAINT)

    validate_check_constraint :places, name: VISIT_RADIUS_CONSTRAINT
  end

  def down; end
end

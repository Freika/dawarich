# frozen_string_literal: true

class AddPlaceVisitRadiusAndVisitLabels < ActiveRecord::Migration[8.0]
  VISIT_RADIUS_CONSTRAINT = 'places_visit_radius_positive'

  def up
    add_column :places, :visit_radius, :integer, default: 50, null: false unless column_exists?(:places, :visit_radius)

    unless check_constraint_exists?(:places, name: VISIT_RADIUS_CONSTRAINT)
      add_check_constraint :places, 'visit_radius > 0', name: VISIT_RADIUS_CONSTRAINT, validate: false
    end

    add_column :visits, :location_label, :string unless column_exists?(:visits, :location_label)
    change_column_null :visits, :name, true
  end

  def down
    change_column_null :visits, :name, false, 'Unknown place'
    remove_column :visits, :location_label if column_exists?(:visits, :location_label)

    if check_constraint_exists?(:places, name: VISIT_RADIUS_CONSTRAINT)
      remove_check_constraint :places, name: VISIT_RADIUS_CONSTRAINT
    end

    remove_column :places, :visit_radius if column_exists?(:places, :visit_radius)
  end
end

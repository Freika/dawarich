# frozen_string_literal: true

class AddPlacesUserIdNotNullCheck < ActiveRecord::Migration[8.0]
  CONSTRAINT_NAME = 'places_user_id_not_null'

  def up
    return if constraint_exists?

    add_check_constraint :places, 'user_id IS NOT NULL', name: CONSTRAINT_NAME, validate: false
  end

  def down
    return unless constraint_exists?

    remove_check_constraint :places, name: CONSTRAINT_NAME
  end

  private

  # Scoped to this table and to CHECK constraints only: PostgreSQL 17+ also
  # catalogues column NOT NULL constraints in pg_constraint under a colliding name.
  def constraint_exists?
    connection.select_value(
      ActiveRecord::Base.sanitize_sql(
        ["SELECT 1 FROM pg_constraint WHERE conrelid = 'places'::regclass AND contype = 'c' AND conname = ?",
         CONSTRAINT_NAME]
      )
    ).present?
  end
end

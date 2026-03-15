# frozen_string_literal: true

# NOTE: This migration intentionally uses raw SQL instead of the User model.
# Loading User during migrations fails when later migrations (e.g. AddPlanToUsers)
# haven't run yet, because the model's enum declarations reference columns that
# don't exist in the database at this point in the migration sequence.
# See: https://github.com/Freika/dawarich/issues/2362
class SetExistingUsersToMapV1 < ActiveRecord::Migration[8.0]
  def up
    # First, ensure the 'maps' key exists for users that don't have it
    execute <<-SQL.squish
      UPDATE users
      SET settings = jsonb_set(COALESCE(settings, '{}'), '{maps}', '{}')
      WHERE NOT (COALESCE(settings, '{}') ? 'maps')
        AND deleted_at IS NULL
    SQL

    # Then set preferred_version to 'v1' for users who aren't already on v2
    execute <<-SQL.squish
      UPDATE users
      SET settings = jsonb_set(settings, '{maps,preferred_version}', '"v1"')
      WHERE (settings->'maps'->>'preferred_version' IS DISTINCT FROM 'v2')
        AND deleted_at IS NULL
    SQL
  end

  def down
    execute <<-SQL.squish
      UPDATE users
      SET settings = settings #- '{maps,preferred_version}'
      WHERE deleted_at IS NULL
    SQL
  end
end

# frozen_string_literal: true

class RepairOptionalAltitudeInvalidation < ActiveRecord::Migration[8.1]
  def up
    execute File.read(Rails.root.join('db/exploration_invalidation.sql'))
    execute File.read(Rails.root.join('db/achievement_collections_invalidation.sql'))
  end

  # Keep the compatible definitions on rollback; no data or schema is removed.
  def down; end
end

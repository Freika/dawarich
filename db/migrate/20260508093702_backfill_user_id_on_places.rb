# frozen_string_literal: true

class BackfillUserIdOnPlaces < ActiveRecord::Migration[8.0]
  def up
    has_pending = ActiveRecord::Base.connection.select_value(
      'SELECT EXISTS(SELECT 1 FROM places WHERE user_id IS NULL)'
    )

    unless has_pending
      Rails.logger.info('[BackfillUserIdOnPlaces] no places with NULL user_id, skipping')
      return
    end

    DataMigrations::BackfillPlacesUserIdJob.perform_later
    Rails.logger.info('[BackfillUserIdOnPlaces] enqueued DataMigrations::BackfillPlacesUserIdJob')
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Cannot un-backfill user_id; orphan places were deleted'
  end
end

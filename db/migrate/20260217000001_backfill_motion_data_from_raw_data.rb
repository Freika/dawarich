# frozen_string_literal: true

class BackfillMotionDataFromRawData < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::BackfillMotionDataJob.perform_later
  end

  def down
    # no-op: backfill is non-destructive
  end
end

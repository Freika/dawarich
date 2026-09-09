# frozen_string_literal: true

# The 1.10.1 backfill (20260719190000) could not recover deviceTag for Google
# Records imports — the importer never wrote raw_data — so it collapsed every
# device onto `legacy-import-<id>`. Those installs need a second pass now that
# the mapping is read from the uploaded file itself.
class EnqueueGoogleRecordsDeviceTagBackfill < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::RecalculatePerTrackerTracksJob.perform_later
  end

  def down; end
end

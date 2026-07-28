# frozen_string_literal: true

class EnqueueLegacyTrackerIdBackfill < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::RecalculatePerTrackerTracksJob.perform_later
  end

  def down; end
end

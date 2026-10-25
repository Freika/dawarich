# frozen_string_literal: true

class EnqueueHandoffTrackRepair < ActiveRecord::Migration[8.1]
  def up
    DataMigrations::RepairHandoffTracksJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=RepairHandoffTracksJob enqueued=false error=#{e.message}"
  end

  def down; end
end

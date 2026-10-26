# frozen_string_literal: true

class EnqueueAndroidTowerFixRecalculation < ActiveRecord::Migration[8.1]
  def up
    DataMigrations::QueueAndroidTowerFixRecalculationJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=QueueAndroidTowerFixRecalculationJob enqueued=false error=#{e.message}"
  end

  def down; end
end

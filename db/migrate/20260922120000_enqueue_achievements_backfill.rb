# frozen_string_literal: true

class EnqueueAchievementsBackfill < ActiveRecord::Migration[8.1]
  def up
    DataMigrations::BackfillAchievementsJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=BackfillAchievementsJob enqueued=false error=#{e.message}"
  end

  def down; end
end

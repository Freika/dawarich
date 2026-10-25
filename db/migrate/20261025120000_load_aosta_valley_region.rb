# frozen_string_literal: true

class LoadAostaValleyRegion < ActiveRecord::Migration[8.1]
  # The recalculation reads the new region, so it must commit before the
  # job is pushed to Sidekiq.
  disable_ddl_transaction!

  def up
    Achievements::LoadRegions.new.call if Country.any?
    enqueue_recalculation
  end

  def down; end

  private

  def enqueue_recalculation
    DataMigrations::BackfillAchievementsJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=BackfillAchievementsJob enqueued=false error=#{e.message}"
  end
end

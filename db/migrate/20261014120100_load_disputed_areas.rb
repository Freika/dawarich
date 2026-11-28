# frozen_string_literal: true

class LoadDisputedAreas < ActiveRecord::Migration[8.1]
  # The recalculation reads the new areas, so they must commit before the
  # job is pushed to Sidekiq.
  disable_ddl_transaction!

  def up
    Achievements::LoadDisputedAreas.new.call
    Region.where(code: Achievements::Registry::DISPUTED_SUBDIVISIONS).delete_all
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

# frozen_string_literal: true

class LoadAostaValleyRegion < ActiveRecord::Migration[8.1]
  # The rebuild reads the new region, so it must commit before the job is
  # pushed to Sidekiq. Rebuilding everyone, not just stale progress, credits
  # Aosta Valley even when workers on this code ran before the migration.
  disable_ddl_transaction!

  def up
    Achievements::LoadRegions.new.call if Country.any?
    enqueue_rebuild
  end

  def down; end

  private

  def enqueue_rebuild
    Achievements::BulkCheckJob.perform_later(notify: false, rebuild: true)
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=BulkCheckJob enqueued=false error=#{e.message}"
  end
end

# frozen_string_literal: true

class BackfillFamiliesForFamilyPlanUsers < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::BackfillFamiliesForFamilyPlanJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue BackfillFamiliesForFamilyPlanJob: #{e.message}"
  end

  def down
    # no-op: backfill is non-destructive
  end
end

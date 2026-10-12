# frozen_string_literal: true

class BackfillOnboardingCompletedForExistingUsers < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::BackfillOnboardingCompletedJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue BackfillOnboardingCompletedJob: #{e.message}"
  end

  def down
    # no-op: backfill is non-destructive
  end
end

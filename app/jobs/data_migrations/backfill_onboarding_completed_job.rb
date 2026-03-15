# frozen_string_literal: true

class DataMigrations::BackfillOnboardingCompletedJob < ApplicationJob
  queue_as :data_migrations

  def perform
    Rails.logger.info('Starting onboarding_completed backfill job')

    # Mark onboarding as completed for existing users who already have location data.
    # This prevents the new onboarding modal from showing to established users.
    count = User.where(
      "points_count > 0 AND (settings->>'onboarding_completed') IS NULL"
    ).update_all(
      Arel.sql(
        "settings = jsonb_set(COALESCE(settings, '{}'), '{onboarding_completed}', 'true')"
      )
    )

    Rails.logger.info("Completed onboarding_completed backfill. Updated #{count} users")
  end
end

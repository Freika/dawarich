# frozen_string_literal: true

class DataMigrations::MigratePointsLatlonJob < ApplicationJob
  queue_as :data_migrations

  def perform(user_id)
    user = User.find(user_id)

    # rubocop:disable Rails/SkipsModelValidations
    user.tracked_points.update_all('lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)')
    # rubocop:enable Rails/SkipsModelValidations
  end
end

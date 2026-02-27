# frozen_string_literal: true

class DataMigrations::MigratePointsLatlonJob < ApplicationJob
  queue_as :data_migrations

  def perform(user_id)
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.info "#{self.class.name}: User #{user_id} not found, skipping"
      return
    end

    user.points.update_all('lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)')
    # rubocop:enable Rails/SkipsModelValidations
  end
end

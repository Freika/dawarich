# frozen_string_literal: true

class DataMigrations::MigratePlacesLonlatJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)

    # rubocop:disable Rails/SkipsModelValidations
    user.places.update_all('lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)')
    # rubocop:enable Rails/SkipsModelValidations
  end
end

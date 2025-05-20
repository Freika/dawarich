# frozen_string_literal: true

class DataMigrations::SetPointsCountryIdsJob < ApplicationJob
  queue_as :default

  def perform(point_id)
    point = Point.find(point_id)
    country = Country.containing_point(point.lon, point.lat)

    if country.present?
      point.country_id = country.id
      point.save!
    else
      Rails.logger.info("No country found for point #{point.id}")
    end
  end
end

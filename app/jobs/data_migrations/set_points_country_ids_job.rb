# frozen_string_literal: true

class DataMigrations::SetPointsCountryIdsJob < ApplicationJob
  queue_as :default

  def perform(point_id)
    point = Point.find(point_id)
    point.country_id = Country.containing_point(point.lon, point.lat).id
    point.save!
  end
end

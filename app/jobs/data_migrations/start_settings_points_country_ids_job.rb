# frozen_string_literal: true

class DataMigrations::StartSettingsPointsCountryIdsJob < ApplicationJob
  queue_as :data_migrations

  def perform
    Point.where(country_id: nil).find_each do |point|
      DataMigrations::SetPointsCountryIdsJob.perform_later(point.id)
    end
  end
end

# frozen_string_literal: true

class DataMigrations::StartSettingsPointsCountryIdsJob < ApplicationJob
  queue_as :data_migrations

  def perform
    Point.where(country_id: nil).in_batches do |batch|
      batch.pluck(:id).each do |point_id|
        DataMigrations::SetPointsCountryIdsJob.perform_later(point_id)
      end
    end
  end
end

# frozen_string_literal: true

class DataMigrations::MigratePointsDataToColumnsAndTablesJob < ApplicationJob
  queue_as :default

  def perform(point_ids)
    Rails.logger.info(
      "=====Migrating points data for #{point_ids.size} ( #{point_ids.first} - #{point_ids.last} ) points====="
    )
    points = Point.where(id: point_ids)

    points.each { DataMigrations::MigratePoint.new(_1).call }

    Rails.logger.info(
      "=====Migrated #{point_ids.size} ( #{point_ids.first} - #{point_ids.last} ) points====="
    )
  end
end

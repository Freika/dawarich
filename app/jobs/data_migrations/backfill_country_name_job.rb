# frozen_string_literal: true

class DataMigrations::BackfillCountryNameJob < ApplicationJob
  queue_as :data_migrations

  def perform(batch_size: 1000)
    Rails.logger.info('Starting country_name backfill job')

    total_count = Point.where(country_name: nil).count
    processed_count = 0

    Point.where(country_name: nil).find_in_batches(batch_size: batch_size) do |points|
      points.each do |point|
        country_name = determine_country_name(point)
        point.update_column(:country_name, country_name) if country_name.present?
        processed_count += 1
      end

      Rails.logger.info("Backfilled country_name for #{processed_count}/#{total_count} points")
    end

    Rails.logger.info("Completed country_name backfill job. Processed #{processed_count} points")
  end

  private

  def determine_country_name(point)
    # First try the legacy country column
    return point.read_attribute(:country) if point.read_attribute(:country).present?

    # Then try the associated country record
    point.country&.name
  end
end

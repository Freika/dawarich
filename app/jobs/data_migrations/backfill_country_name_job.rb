# frozen_string_literal: true

class DataMigrations::BackfillCountryNameJob < ApplicationJob
  include Resumable

  queue_as :data_migrations

  BATCH_SIZE = 1000

  def perform(batch_size: BATCH_SIZE)
    unless ActiveRecord::Base.connection.column_exists?(:points, :country_name)
      Rails.logger.info('[BackfillCountryName] points is already v2-shaped - nothing to backfill')
      return
    end

    Rails.logger.info('Starting country_name backfill job')

    processed_count = 0

    step :backfill, start: 0 do |step|
      loop do
        points = Point.where(country_name: nil)
                      .where('id > ?', step.cursor)
                      .order(:id)
                      .limit(batch_size)

        break if points.empty?

        points.each do |point|
          name = country_name(point)
          point.update_column(:country_name, name) if name.present?

          processed_count += 1
        end

        Rails.logger.info("Backfilled country_name for #{processed_count} points")

        step.set!(points.last.id)
      end
    end

    Rails.logger.info("Completed country_name backfill job. Processed #{processed_count} points")
  end

  private

  def country_name(point)
    point.read_attribute(:country) || point.country&.name
  end
end

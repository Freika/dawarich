# frozen_string_literal: true

class DataMigrations::BackfillAreasIntoPlacesJob < ApplicationJob
  queue_as :data_migrations

  def perform(batch_size: Places::AreasBackfill::BATCH_SIZE)
    Places::AreasBackfill.new(batch_size: batch_size).call
  end
end

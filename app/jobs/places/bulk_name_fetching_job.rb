# frozen_string_literal: true

class Places::BulkNameFetchingJob < ApplicationJob
  queue_as :places

  def perform
    Places::JobCommands.execute('places.bulk_name_fetch', job_id: job_id) { perform_rails }
  end

  private

  def perform_rails
    Place.where(name: Place::DEFAULT_NAME).in_batches do |batch|
      batch.pluck(:id).each do |place_id|
        Places::NameFetchingJob.perform_later(place_id)
      end
    end
  end
end

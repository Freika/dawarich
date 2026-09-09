# frozen_string_literal: true

class Places::BulkNameFetchingJob < ApplicationJob
  queue_as :places

  def perform
    Place.where(name: Place::DEFAULT_NAME).in_batches do |batch|
      batch.pluck(:id).each do |place_id|
        Places::NameFetchingJob.perform_later(place_id)
      end
    end
  end
end

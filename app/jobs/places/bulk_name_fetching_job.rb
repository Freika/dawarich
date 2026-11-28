# frozen_string_literal: true

class Places::BulkNameFetchingJob < ApplicationJob
  queue_as :places

  def perform
    Place.where(name: Place::DEFAULT_NAME).in_batches do |batch|
      ActiveJob.perform_all_later(batch.pluck(:id).map { |place_id| Places::NameFetchingJob.new(place_id) })
    end
  end
end

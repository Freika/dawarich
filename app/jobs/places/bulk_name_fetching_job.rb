# frozen_string_literal: true

class Places::BulkNameFetchingJob < ApplicationJob
  queue_as :places

  def perform
    Place.where(name: Place::DEFAULT_NAME).find_each do |place|
      Places::NameFetchingJob.perform_later(place.id)
    end
  end
end

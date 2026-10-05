# frozen_string_literal: true

class Places::NameFetchingJob < ApplicationJob
  queue_as :places

  def perform(place_id)
    Places::JobCommands.execute('places.name_fetch', place_id, job_id: job_id) do
      place = Place.find(place_id)
      Places::NameFetcher.new(place).call
    end
  end
end

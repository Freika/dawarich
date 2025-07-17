# frozen_string_literal: true

class Places::NameFetchingJob < ApplicationJob
  queue_as :places

  def perform(place_id)
    place = Place.find(place_id)

    Places::NameFetcher.new(place).call
  end
end

# frozen_string_literal: true

module Trek
  class SyncJob < ApplicationJob
    queue_as :imports

    retry_on Trek::Client::Error, wait: :polynomially_longer, attempts: 5

    def perform(source_id)
      source = TripSource.active.find_by(id: source_id, provider: 'trek')
      return unless source

      Trek::Sync.new(source).call
    end
  end
end

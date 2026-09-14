# frozen_string_literal: true

module Trek
  class ImportTripsJob < ApplicationJob
    queue_as :imports

    BATCH_SIZE = 100

    retry_on Trek::Client::Error, wait: :polynomially_longer, attempts: 5

    def perform(source_id, identifiers, selection_token, offset = 0)
      source = TripSource.active.find_by(id: source_id, provider: 'trek')
      return unless source&.selection_token == selection_token

      synchronizer = Trek::Sync.new(source)
      identifiers.slice(offset, BATCH_SIZE).each do |identifier|
        break unless source.reload.selection_token == selection_token

        synchronizer.import!(identifier)
      end
      return unless source.reload.selection_token == selection_token

      next_offset = offset + BATCH_SIZE
      if next_offset < identifiers.length
        self.class.set(wait: 1.minute).perform_later(source_id, identifiers, selection_token, next_offset)
      elsif source.reload.selection_token == selection_token
        source.trips.source_active.where.not(source_identifier: identifiers).update_all(
          source_status: Trip.source_statuses.fetch('stopped'), source_synced_at: Time.current
        )
      end
    end
  end
end

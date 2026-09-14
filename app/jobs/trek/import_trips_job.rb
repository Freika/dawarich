# frozen_string_literal: true

module Trek
  class ImportTripsJob < ApplicationJob
    queue_as :imports

    BATCH_SIZE = 100

    retry_on Trek::Client::Error, wait: :polynomially_longer, attempts: 5

    def perform(source_id, identifiers, selection_token, offset = 0)
      source = TripSource.active.find_by(id: source_id, provider: 'trek')
      return unless source&.selection_token == selection_token

      completed = ActiveRecord::Base.with_advisory_lock("trek-sync:#{source.id}", timeout_seconds: 0) do
        source.reload
        next unless source.selection_token == selection_token && source.importing?

        synchronizer = Trek::Sync.new(source)
        identifiers.slice(offset, BATCH_SIZE).each do |identifier|
          detail = synchronizer.fetch_trip(identifier)
          persisted = source.with_lock do
            if source.selection_token == selection_token && source.importing?
              synchronizer.import_payload!(identifier, detail)
              true
            else
              false
            end
          end
          break unless persisted
        end
        source.reload.selection_token == selection_token && source.importing?
      end
      source.reload
      return unless source.selection_token == selection_token && source.importing?

      unless completed
        return self.class.set(wait: 1.minute).perform_later(source_id, identifiers, selection_token, offset)
      end

      next_offset = offset + BATCH_SIZE
      if next_offset < identifiers.length
        self.class.set(wait: 1.minute).perform_later(source_id, identifiers, selection_token, next_offset)
      elsif source.reload.selection_token == selection_token && source.importing?
        source.with_lock do
          if source.selection_token == selection_token && source.importing?
            source.trips.source_active.where.not(source_identifier: identifiers).update_all(
              source_status: Trip.source_statuses.fetch('stopped'), source_synced_at: Time.current
            )
            source.update!(importing: false, last_synced_at: Time.current)
          end
        end
      end
    rescue Trek::Client::Error
      source.update!(importing: false) if source&.selection_token == selection_token
      raise
    end
  end
end

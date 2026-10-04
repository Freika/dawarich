# frozen_string_literal: true

module Trek
  class SyncJob < ApplicationJob
    queue_as :imports

    retry_on Trek::Client::Error, wait: :polynomially_longer, attempts: 5

    BATCH_SIZE = 100

    def perform(source_id, after_id = nil)
      result = PhoenixLease.try_hold("trek-sync:#{source_id}") do
        Imports::IntegrationCommands.legacy('imports.trek_sync') { perform_legacy(source_id, after_id) }
      end
      return result unless result == :not_owner

      Imports::TrekCommands.forward('imports.trek_sync', { 'source_id' => source_id, 'after_id' => after_id },
                                    event_id: job_id)
    end

    private

    def perform_legacy(source_id, after_id)
      source = TripSource.active.find_by(id: source_id, provider: 'trek')
      return unless source&.sync_allowed? && !source.importing?

      result = nil
      source.reload
      result = Trek::Sync.new(source).call(limit: BATCH_SIZE, after_id:) unless source.importing?
      return unless result

      self.class.set(wait: 1.minute).perform_later(source.id, result.next_cursor) if result.more
    end
  end
end

# frozen_string_literal: true

module Trek
  class SyncJob < ApplicationJob
    queue_as :imports

    retry_on Trek::Client::Error, wait: :polynomially_longer, attempts: 5

    BATCH_SIZE = 100

    def perform(source_id, after_id = nil)
      source = TripSource.active.find_by(id: source_id, provider: 'trek')
      return unless source && !source.importing?

      result = nil
      locked = ActiveRecord::Base.with_advisory_lock("trek-sync:#{source.id}", timeout_seconds: 0) do
        source.reload
        unless source.importing?
          result = Trek::Sync.new(source).call(limit: BATCH_SIZE, after_id:)
          true
        end
      end
      return unless locked && result

      self.class.set(wait: 1.minute).perform_later(source.id, result.next_cursor) if result.more
    end
  end
end

# frozen_string_literal: true

module Imports
  module TrekCommands
    COMMANDS = {
      'imports.trek_import' => {
        version: 1,
        sidekiq: lambda { |payload, at|
          JobCommands.enqueue_after_commit(nil) do
            args = [payload.fetch('source_id'), payload.fetch('identifiers'), payload.fetch('selection_token')]
            args << payload.fetch('offset') unless payload.fetch('offset').zero?
            Trek::ImportTripsJob.set(wait_until: at).perform_later(*args)
          end
        }
      },
      'imports.trek_sync' => {
        version: 1,
        sidekiq: lambda { |payload, at|
          JobCommands.enqueue_after_commit(nil) do
            args = [payload.fetch('source_id')]
            args << payload.fetch('after_id') unless payload.fetch('after_id').nil?
            Trek::SyncJob.set(wait_until: at).perform_later(*args)
          end
        }
      }
    }.freeze

    module_function

    def forward(type, payload, event_id:)
      ActiveRecord::Base.transaction do
        next false unless JobOwnership.lock_owner("command:#{type}") == :oban

        JobCommands.forward(type, payload, event_id:, aggregate_id: payload.fetch('source_id'), producer: 'Trek job')
        true
      end
    end

    def select(source, identifiers)
      ActiveRecord::Base.transaction do
        JobOwnership.lock_owner('command:imports.trek_import')
        source.with_lock do
          next unless source.active? && !source.importing?

          token = SecureRandom.uuid
          source.update!(selection_token: token, importing: true)
          JobCommands.produce('imports.trek_import',
                              { 'source_id' => source.id, 'identifiers' => identifiers,
                                'selection_token' => token, 'offset' => 0 },
                              aggregate_id: source.id, producer: 'Trek selection')
          token
        end
      end
    end
  end
end

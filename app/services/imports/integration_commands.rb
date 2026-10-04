# frozen_string_literal: true

module Imports
  module IntegrationCommands
    COMMANDS = {
      'imports.photoprism_geodata' => {
        version: 1,
        sidekiq: lambda { |payload, at|
          JobCommands.enqueue_after_commit(nil) do
            Time.use_zone(payload.fetch('time_zone')) do
              Import::PhotoprismGeodataJob.set(wait_until: at).perform_later(payload.fetch('user_id'))
            end
          end
        }
      },
      'imports.immich_geodata' => {
        version: 1,
        sidekiq: lambda { |payload, at|
          JobCommands.enqueue_after_commit(nil) do
            Time.use_zone(payload.fetch('time_zone')) do
              Import::ImmichGeodataJob.set(wait_until: at).perform_later(payload.fetch('user_id'))
            end
          end
        }
      }
    }.freeze

    module_function

    def legacy(type)
      error = nil
      result = JobOwnership.with_owner("command:#{type}") do
        yield
      rescue StandardError => e
        error = e
        nil
      end
      raise error if error

      result
    end

    def forward(provider, user_id, event_id:, time_zone: Time.zone.name)
      type = "imports.#{provider}_geodata"
      ActiveRecord::Base.transaction do
        next false unless JobOwnership.lock_owner("command:#{type}") == :oban

        JobCommands.forward(type, { 'user_id' => user_id, 'time_zone' => time_zone },
                            event_id:, aggregate_id: user_id, producer: "Import #{provider} geodata")
        true
      end
    end
  end
end

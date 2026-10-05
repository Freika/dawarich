# frozen_string_literal: true

module Geocoding
  module NightlyCommands
    HANDLERS = {
      'geocoding.reverse_point' => {
        guard: 'Current owner dispatch preserves force and point batches; repeated source leaves converge',
        call: ->(payload) { reverse_point(payload) }
      }
    }.freeze

    module_function

    def reverse_point(payload)
      data = payload.except('event_id')
      ActiveRecord::Base.transaction do
        if JobOwnership.lock_owner('command:geocoding.reverse_point') == :oban
          JobCommands.forward('geocoding.reverse_point', data, event_id: payload.fetch('event_id'),
                              aggregate_id: payload.fetch('user_id'), producer: name)
        else
          JobCommands::COMMANDS.fetch('geocoding.reverse_point').fetch(:sidekiq).call(data, Time.current)
        end
      end
    end
  end
end

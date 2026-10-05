# frozen_string_literal: true

module Geocoding
  module NightlyCommands
    KEY = 'cron:nightly_reverse_geocoding_job'
    HANDLERS = {
      'geocoding.reverse_point' => {
        guard: 'Current owner dispatch preserves force and point batches; repeated source leaves converge',
        call: ->(payload) { reverse_point(payload) }
      }
    }.freeze

    module_function

    def root(slot)
      Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "geocoding.nightly:cron:#{slot}") if slot
    end

    def claim(root, point_id)
      return true if root.nil? || !PhoenixSchema.table?('processed_commands')

      event = Digest::UUID.uuid_v5(root, "scheduled:#{point_id}")
      sql = 'INSERT INTO phoenix.processed_commands(event_id,handler,processed_at) ' \
            'VALUES(?::uuid,?,?) ON CONFLICT(event_id) DO NOTHING RETURNING event_id'
      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array([sql, event, name, Time.current])
      ).present?
    end

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

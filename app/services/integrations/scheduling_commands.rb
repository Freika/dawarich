# frozen_string_literal: true

module Integrations
  module SchedulingCommands
    HANDLERS = {
      'integrations.airtrail_flights' => {
        guard: 'The unchanged import leaf upserts source flights; repeat delivery repeats a convergent sync',
        call: ->(payload) { airtrail_flights(payload) }
      }
    }.freeze

    module_function

    def sweep(scope, kind, key, slot)
      return if JobOwnership.with_owner(key) { :owned } == :not_owner

      scope.in_batches(of: 1000) do |batch|
        result = JobOwnership.with_owner(key) do
          yield batch.pluck(:id), kind, slot
        end
        break if result == :not_owner
      end
    end

    def slot(job, marker)
      raise ArgumentError, 'invalid cron marker' unless marker.nil? || marker == 'a12d2_cron'

      return if marker.nil? && job.enqueued_at.nil?

      (job.enqueued_at || Time.current).to_i / 60 * 60
    end

    def event_id(kind, slot, row_id)
      return SecureRandom.uuid if slot.nil?

      Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "integrations.#{kind}:#{slot}:#{row_id}")
    end

    def claim(kind, slot, row_id)
      return true if slot.nil? || !PhoenixSchema.table?('processed_commands')

      receipt = event_id("#{kind}.scheduled", slot, row_id)
      query = 'INSERT INTO phoenix.processed_commands (event_id, handler, processed_at) ' \
              'VALUES (?::uuid, ?, ?) ON CONFLICT (event_id) DO NOTHING RETURNING event_id'
      statement = ActiveRecord::Base.sanitize_sql_array([query, receipt, name, Time.current])
      ActiveRecord::Base.connection.select_value(statement).present?
    end

    def schedule_airtrail(ids, kind, slot)
      owner = JobOwnership.lock_owner(ImportCommands::AIRTRAIL_FLIGHTS_KEY)
      ids.each do |user_id|
        next unless claim(kind, slot, user_id)

        if owner == :oban
          JobCommands.forward(ImportCommands::AIRTRAIL_FLIGHTS, { 'user_id' => user_id },
                              event_id: event_id(kind, slot, user_id), aggregate_id: user_id, producer: name,
                              dedupe_key: "airtrail:#{user_id}")
        else
          ImportCommands.airtrail_flights(user_id, producer: name)
        end
      end
    end

    def airtrail_flights(payload)
      user_id = payload.fetch('user_id')
      return unless User.exists?(id: user_id)

      AirTrail::ImportFlightsJob.perform_later(user_id)
    end
  end
end

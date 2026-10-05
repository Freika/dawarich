# frozen_string_literal: true

module Integrations
  module SchedulingCommands
    HANDLERS = {
      'integrations.airtrail_flights' => {
        guard: 'The unchanged import leaf upserts source flights; repeat delivery repeats a convergent sync',
        call: ->(payload) { airtrail_flights(payload) }
      },
      'integrations.teslamate_sync' => {
        guard: 'The unchanged TeslaMate leaf imports only missing drives; replay repeats a convergent sync',
        call: ->(payload) { teslamate_sync(payload) }
      },
      'integrations.trek_sync' => {
        guard: 'The unchanged Trek leaf upserts source trips and skips importing sources on replay',
        call: ->(payload) { trek_sync(payload) }
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

      return if job.enqueued_at.nil?

      job.enqueued_at.to_i / 60 * 60
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
          RailsCommands::Poller.publish('integrations.airtrail_flights',
                                        { 'user_id' => user_id, 'event_id' => event_id(kind, slot, user_id) })
        end
      end
    end

    def airtrail_flights(payload)
      user_id = payload.fetch('user_id')
      return unless User.exists?(id: user_id)

      AirTrail::ImportFlightsJob.perform_later(user_id) || raise('AirTrail enqueue aborted')
    end

    def schedule_teslamate(ids, kind, slot)
      ids.each do |user_id|
        next unless claim(kind, slot, user_id)

        RailsCommands::Poller.publish('integrations.teslamate_sync',
                                      { 'user_id' => user_id, 'event_id' => event_id(kind, slot, user_id) })
      end
    end

    def schedule_trek(ids, kind, slot)
      TripSource.where(id: ids).pluck(:id, :user_id).each do |source_id, user_id|
        next unless DawarichSettings.self_hosted? || User.select(:id, :plan).find(user_id).full_access?
        next unless claim(kind, slot, source_id)

        RailsCommands::Poller.publish('integrations.trek_sync',
                                      { 'user_id' => user_id, 'source_id' => source_id,
                                        'event_id' => event_id(kind, slot, source_id) })
      end
    end

    def teslamate_sync(payload)
      user_id = payload.fetch('user_id')
      return unless User.exists?(id: user_id)

      TeslaMate::SyncJob.perform_later(user_id) || raise('TeslaMate enqueue aborted')
    end

    def trek_sync(payload)
      user_id = payload.fetch('user_id')
      source_id = payload.fetch('source_id')
      return unless User.exists?(id: user_id) && TripSource.exists?(id: source_id, user_id: user_id)

      Trek::SyncJob.perform_later(source_id) || raise('Trek enqueue aborted')
    end
  end
end

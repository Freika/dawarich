# frozen_string_literal: true

module Trips::CalculationReceipts
  module_function

  def event_id(trip_id, token)
    Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "trips.calculate:#{trip_id}:#{token}")
  end

  def with_effect(trip_id, token, kind)
    JobOwnership.with_owner(Trips::CalculateAllJob::OWNER_KEY) do
      if token && PhoenixSchema.table?('processed_commands')
        root = event_id(trip_id, token)
        ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.sanitize_sql_array(
            ['SELECT pg_advisory_xact_lock(hashtextextended(?::text, 0))', root]
          )
        )
        next if done?(root) || !claim(Digest::UUID.uuid_v5(root, kind))
      end
      yield
    end
  end

  def complete?(trip_id, token)
    return false unless PhoenixSchema.table?('processed_commands')

    root = event_id(trip_id, token)
    %w[path distance countries].all? { |kind| done?(Digest::UUID.uuid_v5(root, kind)) }
  end

  def finish(trip_id, token)
    return true unless PhoenixSchema.table?('processed_commands')

    claim(event_id(trip_id, token))
  end

  def done?(event)
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(
        ['SELECT 1 FROM phoenix.processed_commands WHERE event_id = ?::uuid', event]
      )
    ).present?
  end

  def claim(event)
    sql = 'INSERT INTO phoenix.processed_commands(event_id,handler,processed_at) ' \
          'VALUES(?::uuid,?,?) ON CONFLICT(event_id) DO NOTHING RETURNING event_id'
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array([sql, event, name, Time.current])
    ).present?
  end
end

# frozen_string_literal: true

module RackAttack
  class PhoenixCounterStore
    INCREMENT = <<~SQL.squish
      INSERT INTO phoenix.counters AS c (key, value, expires_at)
      VALUES (?, ?, statement_timestamp() + make_interval(secs => ?))
      ON CONFLICT (key) DO UPDATE SET
        value = CASE WHEN c.expires_at <= statement_timestamp() THEN EXCLUDED.value ELSE c.value + EXCLUDED.value END,
        expires_at = CASE WHEN c.expires_at <= statement_timestamp() THEN EXCLUDED.expires_at ELSE c.expires_at END
      RETURNING value
    SQL

    def increment(name, amount = 1, expires_in:, **)
      return unless table?

      connection.select_value(ActiveRecord::Base.sanitize_sql_array([INCREMENT, name, amount, expires_in.to_i]))
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("event=rack_attack.store_unavailable error=#{e.class}")
      nil
    end

    def write(_name, _value, **) = true

    private

    def table?
      return true if @table

      @table = connection.select_value("SELECT to_regclass('phoenix.counters') IS NOT NULL")
      if !@table && !@warned
        Rails.logger.warn('event=rack_attack.store_unavailable reason=table_missing')
        @warned = true
      end
      @table
    end

    def connection = ActiveRecord::Base.connection
  end
end

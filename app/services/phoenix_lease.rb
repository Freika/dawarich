# frozen_string_literal: true

module PhoenixLease
  TTL = 60
  MAX_RENEW_ERRORS = 3
  ACQUIRE = <<~SQL
    WITH current AS (
      SELECT name, expires_at FROM phoenix.leases WHERE name = $1 FOR UPDATE SKIP LOCKED
    ), taken AS (
      UPDATE phoenix.leases l
      SET holder = $2, expires_at = statement_timestamp() + make_interval(secs => $3)
      FROM current c
      WHERE l.name = c.name AND c.expires_at <= statement_timestamp()
      RETURNING 1
    ), inserted AS (
      INSERT INTO phoenix.leases (name, holder, expires_at)
      SELECT $1, $2, statement_timestamp() + make_interval(secs => $3)
      WHERE NOT EXISTS (SELECT 1 FROM phoenix.leases WHERE name = $1)
      ON CONFLICT (name) DO NOTHING
      RETURNING 1
    )
    SELECT 1 FROM taken UNION ALL SELECT 1 FROM inserted
  SQL
  RENEW = <<~SQL
    UPDATE phoenix.leases SET expires_at = statement_timestamp() + make_interval(secs => $3)
    WHERE name = $1 AND holder = $2 AND expires_at > statement_timestamp()
  SQL
  RELEASE = 'DELETE FROM phoenix.leases WHERE name = $1 AND holder = $2'

  module_function

  def hold(name, busy, ttl: TTL)
    return yield unless table?

    holder = SecureRandom.uuid
    raise busy unless acquire(name, holder, ttl)

    stop = Queue.new
    beat = Thread.new { heartbeat(name, holder, ttl, stop) }
    begin
      yield
    ensure
      stop << true
      beat.join
      quietly { release(name, holder) }
    end
  end

  def acquire(name, holder, ttl) = changed?(ACQUIRE, name, holder, ttl)

  def renew(name, holder, ttl) = changed?(RENEW, name, holder, ttl)

  def release(name, holder) = changed?(RELEASE, name, holder)

  def table?
    ActiveRecord::Base.connection.select_value("SELECT to_regclass('phoenix.leases') IS NOT NULL")
  end

  def heartbeat(name, holder, ttl, stop)
    errors = 0
    until stop.pop(timeout: ttl / 3.0)
      case quietly { renew(name, holder, ttl) }
      when true then errors = 0
      when false then return lost(name, 'renew_lost')
      else
        errors += 1
        return lost(name, 'consecutive_renew_errors') if errors >= MAX_RENEW_ERRORS
      end
    end
  end

  def lost(name, reason)
    Rails.logger.warn("event=state.lease_lost name=#{name} reason=#{reason}")
  end

  def quietly
    yield
  rescue ActiveRecord::ActiveRecordError
    :error
  end

  def changed?(sql, *binds)
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      connection.exec_update(sql, 'PhoenixLease', binds) == 1
    end
  end

  private_class_method :heartbeat, :lost, :quietly, :changed?
end

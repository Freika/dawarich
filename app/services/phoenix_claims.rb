# frozen_string_literal: true

module PhoenixClaims
  CLAIM = <<~SQL
    INSERT INTO phoenix.once_claims AS c (key, expires_at)
    VALUES ($1, statement_timestamp() + make_interval(secs => $2))
    ON CONFLICT (key) DO UPDATE SET expires_at = EXCLUDED.expires_at
    WHERE c.expires_at <= statement_timestamp()
  SQL
  CLAIM_ALL = <<~SQL
    INSERT INTO phoenix.once_claims AS c (key, expires_at)
    SELECT k, statement_timestamp() + make_interval(secs => $2) FROM unnest($1::text[]) AS k ORDER BY k
    ON CONFLICT (key) DO UPDATE SET expires_at = EXCLUDED.expires_at
    WHERE c.expires_at <= statement_timestamp()
    RETURNING key
  SQL
  SLIDE = <<~SQL
    UPDATE phoenix.once_claims SET expires_at = statement_timestamp() + make_interval(secs => $2)
    WHERE key = $1 AND expires_at > statement_timestamp()
  SQL
  UNCLAIM = 'DELETE FROM phoenix.once_claims WHERE key = $1'
  UNCLAIM_ALL = 'DELETE FROM phoenix.once_claims WHERE key = ANY($1::text[])'

  module_function

  def claim_persistent_all(keys)
    keys = keys.uniq.sort
    return [] if keys.empty?

    unless table?
      script = "if redis.call('SET', KEYS[1], '1', 'NX') then return 1 end " \
               "redis.call('PERSIST', KEYS[1]); return 0"
      results = Sidekiq.redis { |r| r.pipelined { |p| keys.each { p.call('EVAL', script, 1, _1) } } }
      return keys.zip(results).filter_map { |key, result| key if result == 1 }
    end

    connection.transaction do
      sql = CLAIM_ALL.sub('statement_timestamp() + make_interval(secs => $2)', "'infinity'::timestamptz")
      claimed = connection.exec_query(sql, 'PhoenixClaims', [text_array(keys)]).rows.flatten
      update("UPDATE phoenix.once_claims SET expires_at = 'infinity' WHERE key = ANY($1::text[])", text_array(keys))
      claimed
    end
  end

  def claim(key, ttl)
    return Sidekiq.redis { |r| r.set(key, 1, nx: true, ex: ttl) } == 'OK' unless table?

    update(CLAIM, key, ttl) == 1
  end

  def claim_all(keys, ttl)
    keys = keys.uniq
    return [] if keys.empty?
    return redis_claim_all(keys, ttl) unless table?

    connection.exec_query(CLAIM_ALL, 'PhoenixClaims', [text_array(keys), ttl]).rows.flatten
  end

  def debounce(key, ttl)
    return redis_debounce(key, ttl) unless table?
    return true if update(CLAIM, key, ttl) == 1

    update(SLIDE, key, ttl)
    false
  end

  def unclaim(key)
    table? ? update(UNCLAIM, key) : Sidekiq.redis { |r| r.del(key) }
    nil
  end

  def unclaim_all(keys)
    return if keys.empty?

    table? ? update(UNCLAIM_ALL, text_array(keys)) : Sidekiq.redis { |r| r.pipelined { |p| keys.each { p.del(_1) } } }
    nil
  end

  def table? = PhoenixSchema.table?('once_claims')

  def redis_claim_all(keys, ttl)
    results = Sidekiq.redis { |r| r.pipelined { |p| keys.each { p.set(_1, 1, nx: true, ex: ttl) } } }
    keys.zip(results).filter_map { |key, claimed| key if claimed }
  end

  def redis_debounce(key, ttl)
    Sidekiq.redis do |r|
      next true if r.set(key, 1, nx: true, ex: ttl)

      r.expire(key, ttl)
      false
    end
  end

  def update(sql, *binds) = connection.exec_update(sql, 'PhoenixClaims', binds)

  def text_array(keys) = PG::TextEncoder::Array.new.encode(keys)

  def connection = ActiveRecord::Base.connection

  private_class_method :redis_claim_all, :redis_debounce, :update, :text_array, :connection
end

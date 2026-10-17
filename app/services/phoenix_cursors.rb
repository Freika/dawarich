# frozen_string_literal: true

module PhoenixCursors
  CURSOR = 'SELECT value FROM phoenix.cursors WHERE key = $1'
  PUT_CURSOR = <<~SQL
    INSERT INTO phoenix.cursors (key, value, updated_at) VALUES ($1, $2, statement_timestamp())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at
  SQL
  DELETE_CURSOR = 'DELETE FROM phoenix.cursors WHERE key = $1'
  INCREMENT_CURSOR = <<~SQL
    INSERT INTO phoenix.cursors AS c (key, value, updated_at) VALUES ($1, '1', statement_timestamp())
    ON CONFLICT (key) DO UPDATE SET value = (c.value::bigint + 1)::text, updated_at = EXCLUDED.updated_at
    RETURNING value::bigint
  SQL

  module_function

  def get(key)
    return Sidekiq.redis { |redis| redis.get(key) } unless table?

    query(CURSOR, key).rows.first&.first
  end

  def set(key, value)
    return Sidekiq.redis { |redis| redis.set(key, value) } unless table?

    query(PUT_CURSOR, key, value.to_s)
  end

  def del(key)
    return Sidekiq.redis { |redis| redis.del(key) } unless table?

    query(DELETE_CURSOR, key)
  end

  def incr(key)
    return Sidekiq.redis { |redis| redis.incr(key) } unless table?

    query(INCREMENT_CURSOR, key).rows.first.first
  end

  def table?
    ActiveRecord::Base.connection.select_value("SELECT to_regclass('phoenix.cursors') IS NOT NULL")
  end

  def query(sql, *binds)
    ActiveRecord::Base.connection.exec_query(sql, 'PhoenixCursors', binds)
  end

  private_class_method :query
end

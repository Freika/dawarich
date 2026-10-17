# frozen_string_literal: true

module Achievements
  module PendingChecks
    TTL = 3.days.to_i
    DEFER = <<~SQL
      INSERT INTO phoenix.achievement_checks AS c (user_id, oldest_timestamp, revision, expires_at)
      VALUES ($1, $2, nextval('phoenix.achievement_check_revisions'), statement_timestamp() + make_interval(secs => $3))
      ON CONFLICT (user_id) DO UPDATE SET
        oldest_timestamp = CASE WHEN c.expires_at <= statement_timestamp() THEN EXCLUDED.oldest_timestamp
                                ELSE LEAST(c.oldest_timestamp, EXCLUDED.oldest_timestamp) END,
        revision = nextval('phoenix.achievement_check_revisions'),
        expires_at = EXCLUDED.expires_at
    SQL
    READ = 'SELECT oldest_timestamp, revision FROM phoenix.achievement_checks ' \
           'WHERE user_id = $1 AND expires_at > statement_timestamp()'
    CONSUME = 'DELETE FROM phoenix.achievement_checks WHERE user_id = $1 AND revision = $2'

    module_function

    def defer(user_id, timestamp)
      return redis_defer(user_id, timestamp) unless table?

      connection.exec_update(DEFER, 'PendingChecks', [user_id, timestamp, TTL])
    end

    def read(user_id)
      return redis_read(user_id) unless table?

      connection.exec_query(READ, 'PendingChecks', [user_id]).rows.first || [nil, nil]
    end

    def consume(user_id, token)
      return if token.nil?
      return redis_consume(user_id, token) if token.is_a?(Array)

      connection.exec_update(CONSUME, 'PendingChecks', [user_id, token])
    end

    def table? = PhoenixSchema.table?('achievement_checks')

    def redis_defer(user_id, timestamp)
      key = CheckJob.pending_key(user_id)
      Sidekiq.redis do |redis|
        redis.zadd(key, timestamp, "#{timestamp}:#{SecureRandom.hex(4)}")
        redis.expire(key, TTL)
      end
    end

    def redis_read(user_id)
      members = Sidekiq.redis { |redis| redis.zrange(CheckJob.pending_key(user_id), 0, -1) }
      members.empty? ? [nil, nil] : [members.map(&:to_i).min, members]
    end

    def redis_consume(user_id, members) = Sidekiq.redis { |redis| redis.zrem(CheckJob.pending_key(user_id), members) }

    def connection = ActiveRecord::Base.connection

    private_class_method :redis_defer, :redis_read, :redis_consume, :connection
  end
end

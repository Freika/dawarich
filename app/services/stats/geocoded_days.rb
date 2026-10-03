# frozen_string_literal: true

module Stats
  class GeocodedDays
    PENDING_KEY = 'stats:geocoded_days:pending'
    VERSION_KEY_PREFIX = 'stats:geocoded_days:version'
    DELAY = 1.hour
    MARK = <<~SQL
      INSERT INTO phoenix.stats_geocoded_days (member, version, due_at) VALUES ($1, $2, $3)
      ON CONFLICT (member) DO UPDATE SET version = EXCLUDED.version
    SQL
    DUE = <<~SQL
      SELECT member, version FROM phoenix.stats_geocoded_days WHERE due_at <= $1
      ORDER BY due_at, member COLLATE "C" LIMIT $2
    SQL
    SNAPSHOT = 'SELECT member, version FROM phoenix.stats_geocoded_days WHERE member = ANY($1::text[])'
    ACKNOWLEDGE = <<~SQL
      WITH gone AS (
        DELETE FROM phoenix.stats_geocoded_days WHERE member = $1 AND version = $2 RETURNING 1
      )
      UPDATE phoenix.stats_geocoded_days SET due_at = $3 WHERE member = $1 AND NOT EXISTS (SELECT 1 FROM gone)
    SQL
    POSTPONE = 'UPDATE phoenix.stats_geocoded_days SET due_at = $2 WHERE member = $1'
    DRAIN = <<~SQL
      INSERT INTO phoenix.stats_geocoded_days (member, version, due_at) VALUES ($1, $2, $3)
      ON CONFLICT (member) DO NOTHING
    SQL

    def self.mark(user_id, timestamp)
      member = "#{user_id}:#{Time.at(timestamp).utc.to_date.iso8601}"
      return query(MARK, member, SecureRandom.uuid, due_at) if table?

      Sidekiq.redis do |redis|
        redis.multi do |transaction|
          transaction.call('SET', version_key(member), SecureRandom.uuid)
          transaction.call('ZADD', PENDING_KEY, 'NX', (Time.current + DELAY).to_i, member)
        end
      end
    end

    def self.due(limit:)
      return query(DUE, Time.current.to_i, limit).rows.to_h if table?

      Sidekiq.redis do |redis|
        members = redis.call('ZRANGEBYSCORE', PENDING_KEY, '-inf', Time.current.to_i, 'LIMIT', 0, limit)
        snapshot(redis, members)
      end
    end

    def self.snapshot_month(user, year, month)
      zone = ActiveSupport::TimeZone[user.timezone_iana]
      first = zone.local(year, month, 1)
      last = first.next_month
      days = (first.utc.to_date..last.utc.to_date).select do |date|
        date.to_time(:utc) >= first && (date + 1).to_time(:utc) <= last
      end
      members = days.map { |date| "#{user.id}:#{date.iso8601}" }
      return query(SNAPSHOT, PG::TextEncoder::Array.new.encode(members)).rows.to_h if table?

      Sidekiq.redis { |redis| snapshot(redis, members) }
    rescue RedisClient::Error => e
      Rails.logger.warn("Stats pending snapshot unavailable: #{e.class}: #{e.message}")
      {}
    end

    def self.acknowledge(entries)
      return if entries.empty?
      return entries.each { |member, version| query(ACKNOWLEDGE, member, version, due_at) } if table?

      Sidekiq.redis do |redis|
        entries.each do |member, version|
          key = version_key(member)
          result = redis.multi(watch: [key]) do |transaction|
            if redis.call('GET', key) == version
              transaction.call('DEL', key)
              transaction.call('ZREM', PENDING_KEY, member)
            else
              transaction.call('ZADD', PENDING_KEY, 'XX', (Time.current + DELAY).to_i, member)
            end
          end
          redis.call('ZADD', PENDING_KEY, 'XX', (Time.current + DELAY).to_i, member) unless result
        end
      end
    end

    def self.postpone(member)
      return query(POSTPONE, member, due_at) if table?

      Sidekiq.redis { |redis| redis.call('ZADD', PENDING_KEY, 'XX', (Time.current + DELAY).to_i, member) }
    end

    def self.drain_redis
      return unless table?

      Sidekiq.redis do |redis|
        members = redis.call('ZRANGE', PENDING_KEY, 0, -1)
        next if members.empty?

        snapshot(redis, members).each { |member, version| query(DRAIN, member, version, Time.current.to_i) }
        redis.call('ZREM', PENDING_KEY, *members)
        redis.call('DEL', *members.map { |member| version_key(member) })
      end
    end

    def self.local_months(member, user)
      date = Date.iso8601(member.split(':', 2).last)
      [date.to_time(:utc), (date + 1).to_time(:utc) - 1].map do |time|
        local = time.in_time_zone(user.timezone_iana)
        [local.year, local.month]
      end.uniq
    end

    def self.table?
      ActiveRecord::Base.connection.select_value("SELECT to_regclass('phoenix.stats_geocoded_days') IS NOT NULL")
    end

    def self.snapshot(redis, members)
      return {} if members.empty?

      keys = members.map { |member| version_key(member) }
      members.zip(redis.call('MGET', *keys)).to_h.compact
    end

    def self.version_key(member)
      "#{VERSION_KEY_PREFIX}:#{member}"
    end

    def self.query(sql, *binds)
      ActiveRecord::Base.connection.exec_query(sql, 'Stats::GeocodedDays', binds)
    end

    def self.due_at = (Time.current + DELAY).to_i
    private_class_method :snapshot, :version_key, :query, :due_at
  end
end

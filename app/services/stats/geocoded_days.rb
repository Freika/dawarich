# frozen_string_literal: true

module Stats
  class GeocodedDays
    PENDING_KEY = 'stats:geocoded_days:pending'
    VERSIONS_KEY = 'stats:geocoded_days:versions'
    DELAY = 1.hour
    MARK_SCRIPT = <<~LUA
      redis.call('HSET', KEYS[2], ARGV[1], ARGV[2])
      redis.call('ZADD', KEYS[1], 'NX', ARGV[3], ARGV[1])
      return 1
    LUA
    ACK_SCRIPT = <<~LUA
      if redis.call('HGET', KEYS[2], ARGV[1]) == ARGV[2] then
        redis.call('HDEL', KEYS[2], ARGV[1])
        redis.call('ZREM', KEYS[1], ARGV[1])
        return 1
      end
      redis.call('ZADD', KEYS[1], 'XX', ARGV[3], ARGV[1])
      return 0
    LUA

    def self.mark(user_id, timestamp)
      member = "#{user_id}:#{Time.at(timestamp).utc.to_date.iso8601}"
      Sidekiq.redis do |redis|
        redis.call('EVAL', MARK_SCRIPT, 2, PENDING_KEY, VERSIONS_KEY,
                   member, SecureRandom.uuid, (Time.current + DELAY).to_i)
      end
    end

    def self.due(limit:)
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
      Sidekiq.redis { |redis| snapshot(redis, members) }
    rescue RedisClient::Error => e
      Rails.logger.warn("Stats pending snapshot unavailable: #{e.class}: #{e.message}")
      {}
    end

    def self.acknowledge(entries)
      return if entries.empty?

      Sidekiq.redis do |redis|
        entries.each do |member, version|
          redis.call('EVAL', ACK_SCRIPT, 2, PENDING_KEY, VERSIONS_KEY, member, version, (Time.current + DELAY).to_i)
        end
      end
    end

    def self.postpone(member)
      Sidekiq.redis { |redis| redis.call('ZADD', PENDING_KEY, 'XX', (Time.current + DELAY).to_i, member) }
    end

    def self.local_months(member, user)
      date = Date.iso8601(member.split(':', 2).last)
      [date.to_time(:utc), (date + 1).to_time(:utc) - 1].map do |time|
        local = time.in_time_zone(user.timezone_iana)
        [local.year, local.month]
      end.uniq
    end

    def self.snapshot(redis, members)
      return {} if members.empty?

      members.zip(redis.call('HMGET', VERSIONS_KEY, *members)).to_h.compact
    end
    private_class_method :snapshot
  end
end

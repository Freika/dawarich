# frozen_string_literal: true

module Stats
  class GeocodedDays
    PENDING_KEY = 'stats:geocoded_days:pending'
    VERSION_KEY_PREFIX = 'stats:geocoded_days:version'
    DELAY = 1.hour

    def self.mark(user_id, timestamp)
      member = "#{user_id}:#{Time.at(timestamp).utc.to_date.iso8601}"
      Sidekiq.redis do |redis|
        redis.multi do |transaction|
          transaction.call('SET', version_key(member), SecureRandom.uuid)
          transaction.call('ZADD', PENDING_KEY, 'NX', (Time.current + DELAY).to_i, member)
        end
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

      keys = members.map { |member| version_key(member) }
      members.zip(redis.call('MGET', *keys)).to_h.compact
    end

    def self.version_key(member)
      "#{VERSION_KEY_PREFIX}:#{member}"
    end
    private_class_method :snapshot, :version_key
  end
end

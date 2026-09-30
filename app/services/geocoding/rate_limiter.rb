# frozen_string_literal: true

module Geocoding
  # Paces geocoding lookups so Dawarich stays inside the provider's published
  # requests-per-second limit.
  #
  # Each upstream endpoint gets a "next free slot" timestamp. A caller takes the
  # slot, pushes it one interval forward for whoever is behind it, and sleeps
  # until its turn. A stale slot is dragged up to now first, so sitting idle
  # never banks credit for a burst.
  #
  # The bookkeeping is per process and guarded by a mutex, which is what makes
  # this correct where it matters: Sidekiq runs its whole thread pool in one
  # process, so the backfill that prompted this is paced exactly. A separate
  # process - the web server, or a second worker container - keeps its own
  # count, so the real rate can exceed the setting when both are geocoding at
  # once. Interactive lookups are rare enough for that to stay in the noise.
  #
  # An interactive caller passes max_wait: to bound how long its request
  # thread may sleep. When the next free slot is further away than that, the
  # slot is left untouched for callers that can wait, the block is skipped and
  # throttle returns nil.
  class RateLimiter
    MUTEX = Mutex.new
    MAX_INTERACTIVE_WAIT = 1.0
    KEY_PREFIX = 'geocoding:rate_limit:'
    PROVIDER_KEYS = %w[
      command:geocoding.reverse_point command:geocoding.reverse_place
      command:visits.suggest command:visits.full_history_redetect
    ].freeze
    RESERVE_LUA = <<~LUA
      local clock = redis.call('TIME')
      local now = tonumber(clock[1]) * 1000000 + tonumber(clock[2])
      local slot = tonumber(redis.call('GET', KEYS[1]) or '0')
      if slot < now then slot = now end
      local wait = slot - now
      local max_wait = tonumber(ARGV[2])
      if max_wait >= 0 and wait > max_wait then return -1 end
      local next_slot = slot + tonumber(ARGV[1])
      redis.call('SET', KEYS[1], string.format('%.0f', next_slot), 'PX', string.format('%.0f', math.floor((next_slot - now) / 1000) + 1000))
      return wait
    LUA

    class << self
      def throttle(config, max_wait: nil)
        wait = reserve(config, max_wait)
        if wait.nil?
          Rails.logger.info("[Geocoding::RateLimiter] Skipping #{config.provider} lookup: wait exceeds #{max_wait}s")
          return
        end

        sleep(wait) if wait.positive?

        yield
      end

      def shared?
        ENV['GEOCODING_SHARED_RATE_LIMIT'] == 'true'
      end

      def guard_claim!(key)
        return if shared? || PROVIDER_KEYS.exclude?(key)

        raise ArgumentError, "#{key} calls a geocoding provider: set GEOCODING_SHARED_RATE_LIMIT=true in Rails first"
      end

      def reset!
        MUTEX.synchronize { next_slots.clear }
        Sidekiq.redis { |redis| redis.call('KEYS', "#{KEY_PREFIX}*").each { |key| redis.call('DEL', key) } }
      end

      # Komoot meters per IP, so everyone pointed at it shares one bucket.
      # Keyed providers - ChibiGeo, Geoapify, LocationIQ - meter per API key
      # instead, so two users on one box with their own keys get their own
      # allowance. The key is digested rather than used raw: bucket names end
      # up in logs.
      def key_for(config)
        [config.provider, Providers.bare_host(config.host), key_digest(config)].compact.join(':')
      end

      private

      def reserve(config, max_wait)
        rate = config.rps
        return 0.0 if rate.nil? || rate <= 0
        return local_reserve(config, rate, max_wait) unless shared?

        shared_reserve(config, rate, max_wait)
      rescue RedisClient::Error => e
        Rails.logger.warn("[Geocoding::RateLimiter] shared limiter unavailable, pacing locally: #{e.class}")
        local_reserve(config, rate, max_wait)
      end

      def shared_reserve(config, rate, max_wait)
        max = max_wait ? (max_wait * 1_000_000).round : -1
        wait = Sidekiq.redis do |redis|
          redis.call('EVAL', RESERVE_LUA, 1, "#{KEY_PREFIX}#{key_for(config)}", (1_000_000 / rate).round, max)
        end
        wait.negative? ? nil : wait / 1_000_000.0
      end

      def local_reserve(config, rate, max_wait)
        interval = 1.0 / rate
        key = key_for(config)

        MUTEX.synchronize do
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          slot = [next_slots.fetch(key, now), now].max
          wait = slot - now
          break nil if max_wait && wait > max_wait

          next_slots[key] = slot + interval
          wait
        end
      end

      # Only ever touched inside MUTEX. One entry per endpoint the instance
      # talks to, so it stays a handful of keys.
      def next_slots
        @next_slots ||= {}
      end

      def key_digest(config)
        return unless Providers.metered_per_key?(config.provider, config.host)
        return if config.api_key.blank?

        Digest::SHA256.hexdigest(config.api_key)[0, 12]
      end
    end
  end
end

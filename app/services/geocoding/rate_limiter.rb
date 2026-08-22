# frozen_string_literal: true

module Geocoding
  # Paces geocoding lookups so Dawarich stays inside the provider's published
  # requests-per-second limit.
  #
  # Redis holds one "next free slot" timestamp per upstream endpoint, so every
  # Puma and Sidekiq process on the instance draws from the same line. Reserving
  # a slot is a single atomic script: read the slot, drag it up to now if it is
  # in the past, hand it out and push it one interval further. Callers sleep
  # until their slot comes round.
  #
  # The bucket is keyed on the endpoint rather than the user because Komoot and
  # ChibiGeo meter per IP - three users on one self-hosted box share one real
  # quota, not three.
  class RateLimiter
    NAMESPACE = 'geocoding:rps'

    # A web request gives up its place in line rather than leave someone
    # staring at a spinner; one unpaced lookup now and then is the cheaper
    # trade. A worker has nowhere better to be, and its wait is self-limiting
    # anyway - only as many threads as the process runs can ever be queued, so
    # the wait tops out around concurrency / rps. The cap is a backstop for an
    # absurdly slow rate, not a routine path.
    WEB_MAX_WAIT = 1.0
    JOB_MAX_WAIT = 300.0
    LONG_WAIT_WARN_SECONDS = 10.0

    # Returns the seconds to wait, or -1 when the slot is further out than the
    # caller is willing to wait - in which case nothing is reserved and the
    # place in line stays free for whoever can use it.
    RESERVE_LUA = <<~LUA
      local now = tonumber(ARGV[1])
      local interval = tonumber(ARGV[2])
      local max_wait = tonumber(ARGV[3])
      local slot = tonumber(redis.call("get", KEYS[1]) or "0")
      if slot < now then slot = now end
      local wait = slot - now
      if wait > max_wait then return "-1" end
      redis.call("set", KEYS[1], tostring(slot + interval), "px", math.ceil((wait + interval) * 1000) + 1000)
      return tostring(wait)
    LUA

    class << self
      def throttle(config)
        wait = reserve(config)
        sleep(wait) if wait&.positive?

        yield
      end

      def key_for(config)
        host = Providers.bare_host(config.host).presence || 'default'

        "#{NAMESPACE}:#{config.provider}:#{host}"
      end

      private

      def reserve(config)
        rate = config.rps
        return nil if rate.nil? || rate <= 0

        interval = 1.0 / rate
        wait = reserve_slot(key_for(config), interval).to_f
        return nil if wait.negative?

        warn_long_wait(config, wait)
        wait
      rescue StandardError => e
        Rails.logger.warn("[Geocoding::RateLimiter] #{key_for(config)} unavailable: #{e.class}: #{e.message}")
        nil
      end

      def reserve_slot(key, interval)
        Sidekiq.redis do |redis|
          redis.call('EVAL', RESERVE_LUA, 1, key, Time.current.to_f.to_s, interval.to_s, max_wait.to_s)
        end
      end

      def max_wait
        Sidekiq.server? ? JOB_MAX_WAIT : WEB_MAX_WAIT
      end

      def warn_long_wait(config, wait)
        return if wait < LONG_WAIT_WARN_SECONDS

        Rails.logger.warn(
          "[Geocoding::RateLimiter] waiting #{wait.round(1)}s for #{key_for(config)} at #{config.rps} rps"
        )
      end
    end
  end
end

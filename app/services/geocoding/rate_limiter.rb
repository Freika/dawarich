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
  class RateLimiter
    MUTEX = Mutex.new

    class << self
      def throttle(config)
        wait = reserve(config)
        sleep(wait) if wait.positive?

        yield
      end

      def reset!
        MUTEX.synchronize { next_slots.clear }
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

      def reserve(config)
        rate = config.rps
        return 0.0 if rate.nil? || rate <= 0

        interval = 1.0 / rate
        key = key_for(config)

        MUTEX.synchronize do
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          slot = [next_slots.fetch(key, now), now].max
          next_slots[key] = slot + interval
          slot - now
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

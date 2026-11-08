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
  #
  # A provider that refuses a lookup as over its limit starts a
  # Geocoding::Cooldown. Until it ends, no lookup goes out: an interactive
  # caller gets nil, as for a busy slot, and any other caller gets
  # Geocoding::Cooldown::Active.
  class RateLimiter
    MUTEX = Mutex.new
    MAX_INTERACTIVE_WAIT = 1.0

    class << self
      def throttle(config, max_wait: nil, &)
        return cooling_down(config, max_wait) if Cooldown.active?(config)

        wait = reserve(config, max_wait)
        if wait.nil?
          Rails.logger.info("[Geocoding::RateLimiter] Skipping #{config.provider} lookup: wait exceeds #{max_wait}s")
          return
        end

        if wait.positive?
          sleep(wait)
          # The lookup this one queued behind may have been refused meanwhile.
          return cooling_down(config, max_wait) if Cooldown.active?(config)
        end

        lookup(config, &)
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

      def lookup(config)
        result = yield
        if provider_answered?(result)
          Cooldown.clear(config)
          Points::ResumeReverseGeocodingJob.renew_forced_runs
        end
        result
      rescue Geocoder::OverQueryLimitError
        Cooldown.start(config)
        raise
      end

      # Geocoder serves repeated coordinates from its cache without asking the
      # provider, and an empty result cannot be told apart from a cached one.
      def provider_answered?(result)
        first = Array(result).first
        first.respond_to?(:cache_hit) && first.cache_hit == false
      end

      def cooling_down(config, max_wait)
        if max_wait
          Rails.logger.info("[Geocoding::RateLimiter] Skipping #{config.provider} lookup: provider is over its limit")
          return
        end

        raise Cooldown::Active, "#{Providers.name(config.provider)} is over its limit; lookups are paused"
      end

      def reserve(config, max_wait)
        rate = config.rps
        return 0.0 if rate.nil? || rate <= 0

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

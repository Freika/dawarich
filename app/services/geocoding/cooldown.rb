# frozen_string_literal: true

module Geocoding
  # Remembers that a provider refused a lookup for being over its limit
  # (HTTP 402 or 429), so Dawarich stops asking until the refusal has had time
  # to lift instead of sending every queued lookup into the same refusal.
  #
  # Pacing (Geocoding::RateLimiter) keeps Dawarich inside a requests-per-second
  # limit, but some providers also cap the volume per day or per IP. Public
  # komoot Photon, for one, starts refusing a sustained 1 req/s backlog after a
  # couple of thousand lookups and keeps refusing for hours. Without a cooldown,
  # the rest of a nightly backlog is still sent, one refused request per second.
  #
  # The first refusal pauses lookups for BASE_DURATION. Each further refusal
  # that follows a pause doubles it, up to MAX_DURATION, and a lookup the
  # provider itself answers resets the sequence. The state lives in Redis, keyed
  # by the same bucket as the rate limiter, so the web server and every Sidekiq
  # process pause together, and switching to another provider or API key is not
  # held back by the old one's refusals.
  module Cooldown
    # Raised instead of a lookup while a cooldown is running. It is an
    # OverQueryLimitError, so callers handle it the way they handle the
    # provider's own refusal.
    class Active < Geocoder::OverQueryLimitError; end

    BASE_DURATION = 1.minute
    MAX_DURATION = 1.hour
    # How long a run of refusals is remembered once lookups stop altogether.
    STRIKES_TTL = 1.day
    # Lets a retry land just after the cooldown key has expired.
    RETRY_MARGIN = 2.seconds
    KEY_PREFIX = 'geocoding:cooldown'

    # Starts a cooldown unless one is already running, in one step, so the
    # lookups that were in flight when the limit hit count as one refusal.
    # Returns the cooldown length in seconds, or 0 when one was running.
    START_SCRIPT = <<~LUA
      if redis.call('EXISTS', KEYS[1]) == 1 then return 0 end
      local strikes = redis.call('INCR', KEYS[2])
      redis.call('EXPIRE', KEYS[2], tonumber(ARGV[3]))
      local seconds = math.min(tonumber(ARGV[1]) * 2 ^ (strikes - 1), tonumber(ARGV[2]))
      redis.call('SET', KEYS[1], strikes, 'EX', seconds)
      return seconds
    LUA

    # A success that lands during a cooldown was sent before the refusal, so it
    # says nothing about whether the limit has lifted.
    CLEAR_SCRIPT = <<~LUA
      if redis.call('EXISTS', KEYS[1]) == 0 then redis.call('DEL', KEYS[2]) end
      return 0
    LUA

    class << self
      # Seconds left on the running cooldown, or nil when lookups may go out.
      # Fails open: a Redis outage must not stop geocoding altogether.
      def remaining(config)
        ttl = Sidekiq.redis { |redis| redis.call('TTL', active_key(config)) }
        ttl.positive? ? ttl : nil
      rescue StandardError => e
        Rails.logger.warn("[Geocoding::Cooldown] Could not read the cooldown: #{e.message}")
        nil
      end

      def active?(config)
        remaining(config).present?
      end

      # True from a refusal until the provider itself answers a lookup, which
      # outlasts the cooldown: a cached answer leaves this set.
      def unanswered_refusal?(config)
        Sidekiq.redis { |redis| redis.call('EXISTS', strikes_key(config)) } == 1
      rescue StandardError => e
        Rails.logger.warn("[Geocoding::Cooldown] Could not read the refusals: #{e.message}")
        false
      end

      # How long a lookup dropped because of a cooldown should wait to retry.
      def retry_after(config)
        (remaining(config) || 0) + RETRY_MARGIN.to_i
      end

      # A place retries on its own after the wait, so without this every repeat
      # lookup during a long refusal would add a retry that renews itself. The
      # claim lasts exactly the wait, so the retry can claim again if it is
      # refused. Fails open: a duplicate retry beats losing the only one.
      def claim_retry(key, wait)
        Sidekiq.redis { |redis| redis.call('SET', "#{KEY_PREFIX}:retry:#{key}", '1', 'NX', 'EX', wait) }.present?
      rescue StandardError => e
        Rails.logger.warn("[Geocoding::Cooldown] Could not claim a retry: #{e.message}")
        true
      end

      # Returns the length of the cooldown it started, in seconds, or 0 when
      # one was already running.
      def start(config)
        seconds = Sidekiq.redis do |redis|
          redis.call('EVAL', START_SCRIPT, 2, active_key(config), strikes_key(config),
                     BASE_DURATION.to_i, MAX_DURATION.to_i, STRIKES_TTL.to_i)
        end
        if seconds.positive?
          Rails.logger.warn(
            "[Geocoding::Cooldown] #{describe(config)} refused a lookup as over its limit; " \
            "pausing lookups for #{seconds}s"
          )
        end
        seconds
      rescue StandardError => e
        Rails.logger.warn("[Geocoding::Cooldown] Could not start a cooldown: #{e.message}")
        0
      end

      # Called after a lookup the provider answered: the limit has lifted, so
      # the next refusal starts again from BASE_DURATION.
      def clear(config)
        Sidekiq.redis { |redis| redis.call('EVAL', CLEAR_SCRIPT, 2, active_key(config), strikes_key(config)) }
      rescue StandardError => e
        Rails.logger.warn("[Geocoding::Cooldown] Could not clear the cooldown: #{e.message}")
      end

      # For specs: the state outlives an example, unlike the rate limiter's.
      def reset!
        Sidekiq.redis do |redis|
          keys = redis.call('KEYS', "#{KEY_PREFIX}:*")
          redis.call('DEL', *keys) if keys.any?
        end
      end

      private

      def active_key(config)
        "#{KEY_PREFIX}:#{RateLimiter.key_for(config)}"
      end

      def strikes_key(config)
        "#{active_key(config)}:strikes"
      end

      def describe(config)
        [Providers.name(config.provider), Providers.bare_host(config.host)].compact_blank.join(' at ')
      end
    end
  end
end

# frozen_string_literal: true

# Per-user, per-year cache tokens that invalidate vector-tile ETags whenever
# the user's points change. Tokens are opaque random values, NOT counters:
# a reseeded token can never collide with a previously issued ETag, so Redis
# eviction costs one refetch and can never serve stale content. Year bucketing
# keeps historical tiles cached while live tracking only touches the current
# year. All reads/writes are raw — Rails.cache.increment/fetch interact fatally
# with redis_cache_store serialization, which is why counters were rejected.
#
# If Redis is unavailable, the cache store's failsafe makes these values
# unstable, so ETags never match and every tile request degrades to a full
# response: slower, never stale, never crashing.
class Points::TileEpoch
  KEY_PREFIX = 'points:tile_epoch'
  # Bumped by writers that cannot cheaply know which years they touched;
  # included in every etag_component so it invalidates all ranges.
  SENTINEL_YEAR = 'all'
  MIN_YEAR = 1970
  MAX_YEAR = 2100

  class << self
    def bump(user_id, timestamps: nil)
      write_tokens(user_id, timestamps ? years_from_timestamps(timestamps) : [])
    rescue StandardError => e
      log_bump_failure(user_id, e)
    end

    # For writers that touch a known time WINDOW (not a list of rows): bumps
    # every year the window covers, so multi-year interiors are not missed and
    # the sentinel's whole-cache wipe is avoided on hot paths.
    def bump_range(user_id, start_timestamp, end_timestamp)
      write_tokens(user_id, years_in_range(start_timestamp, end_timestamp))
    rescue StandardError => e
      log_bump_failure(user_id, e)
    end

    def etag_component(user_id, start_timestamp, end_timestamp)
      years = years_in_range(start_timestamp, end_timestamp) + [SENTINEL_YEAR]
      keys = years.map { |year| key(user_id, year) }
      found = Rails.cache.read_multi(*keys, raw: true)

      keys.map { |cache_key| found[cache_key] || seed(cache_key) }.join('-')
    end

    private

    # Empty years (no timestamps, or an inverted/degenerate window) fail
    # CLOSED via the sentinel: over-invalidation costs one refetch, a missed
    # invalidation serves stale tiles indefinitely.
    def write_tokens(user_id, years)
      years = [SENTINEL_YEAR] if years.empty?
      years.each { |year| Rails.cache.write(key(user_id, year), fresh_token, raw: true) }
    end

    # Invalidation must never take down the write path it rides on; the cache
    # store's failsafe already swallows connection errors, this guards the
    # rest (including year derivation on unexpected input).
    def log_bump_failure(user_id, error)
      Rails.logger.warn("TileEpoch bump failed for user #{user_id}: #{error.message}")
    end

    def key(user_id, year)
      "#{KEY_PREFIX}:#{user_id}:#{year}"
    end

    # Timestamps are epoch integers; the year MUST be derived in UTC on both
    # the bump and etag sides, or writes near Dec 31/Jan 1 land in one bucket
    # while requests hash the other and the invalidation is missed.
    def years_from_timestamps(timestamps)
      timestamps.compact.map { |timestamp| utc_year(timestamp) }.uniq
    end

    def years_in_range(start_timestamp, end_timestamp)
      (utc_year(start_timestamp)..utc_year(end_timestamp)).to_a
    end

    def utc_year(timestamp)
      Time.at(timestamp.to_i).utc.year.clamp(MIN_YEAR, MAX_YEAR)
    end

    def fresh_token
      SecureRandom.hex(8)
    end

    # A missing key is seeded (written back) so the ETag stays stable across
    # repeated reads; a concurrent seed race just costs one extra refetch.
    def seed(cache_key)
      fresh_token.tap { |token| Rails.cache.write(cache_key, token, raw: true) }
    end
  end
end

# frozen_string_literal: true

# Deterministic stand-ins for letting a short Redis TTL elapse. The specs used
# to Kernel.sleep against a 1-second TTL, which raced under load (the sleep and
# the Redis expiry are both wall-clock), so the same file could pass one run and
# fail the next. Expiring the keys directly models the same state without time.
module GeocodingTimeHelpers
  # The cooldown's active window has elapsed: its key is gone while the day-long
  # strike count (and any retry claim) survives, exactly as a natural expiry.
  def expire_geocoding_cooldown
    Sidekiq.redis do |redis|
      redis.call('KEYS', "#{Geocoding::Cooldown::KEY_PREFIX}:*")
           .reject { |key| key.end_with?(':strikes') || key.include?(':retry:') }
           .each { |key| redis.call('DEL', key) }
    end
  end

  # Both forced-run keys have expired after FORCED_RUN_TTL, so the run is dropped.
  def expire_forced_runs
    Sidekiq.redis do |redis|
      redis.call('DEL',
                 Points::ResumeReverseGeocodingJob::FORCED_RUNS_KEY,
                 Points::ResumeReverseGeocodingJob::FORCED_RUN_STARTS_KEY)
    end
  end
end

RSpec.configure { |config| config.include GeocodingTimeHelpers }

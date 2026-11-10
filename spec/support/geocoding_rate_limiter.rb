# frozen_string_literal: true

# The rate limiter keeps its slot bookkeeping in process memory for the life of
# the process, so a spec that configures a rate would otherwise leave the next
# spec's first lookup waiting on a real sleep. A cooldown lives in Redis and
# would outlive the spec that hit an over-limit refusal the same way.
RSpec.configure do |config|
  config.before do
    Geocoding::RateLimiter.reset!
    Geocoding::Cooldown.reset!
    Sidekiq.redis do |redis|
      redis.call('DEL', Points::ResumeReverseGeocodingJob::CLAIM_KEY, Points::ResumeReverseGeocodingJob::FORCED_RUNS_KEY)
    end
  end
end

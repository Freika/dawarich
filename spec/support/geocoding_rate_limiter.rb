# frozen_string_literal: true

# The rate limiter keeps its slot bookkeeping in process memory for the life of
# the process, so a spec that configures a rate would otherwise leave the next
# spec's first lookup waiting on a real sleep.
RSpec.configure do |config|
  config.before { Geocoding::RateLimiter.reset! }
end

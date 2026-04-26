# frozen_string_literal: true

# Per-plan API rate limiting using rack-attack with Redis backend.
# Self-hosted instances are exempt from rate limiting entirely.
# Cloud plans: Lite = 200 req/hr, Pro = 1,000 req/hr.
# Points creation endpoints: 10,000 req/hr (all plans, including self-hosted).

Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
  url: ENV['REDIS_URL'],
  db: ENV.fetch('RACK_ATTACK_REDIS_DB', '3').to_i # dbs 0-2 are reserved for app caching, sidekiq and ws.
)

# Disabled in the test environment so request specs aren't throttled by
# accumulated counters across examples (login throttle is 5/min by IP,
# 20/min by email — easy to trip when many specs hit /users/sign_in).
# `spec/requests/api/v1/rate_limiting_spec.rb` re-enables it locally to
# exercise the throttling behavior.
Rack::Attack.enabled = false if Rails.env.test?

# Configurable per-plan limits. Override in tests via Rack::Attack.api_rate_limits=
class Rack::Attack
  class << self
    attr_accessor :api_rate_limits
  end
  self.api_rate_limits = { 'lite' => 200, 'pro' => 1_000 }
end

# Dynamic per-user rate limiting keyed by API token.
# Execution order: rack-attack evaluates the discriminator block first (which sets
# the per-user limit in req.env), then evaluates the limit proc (which reads it).
Rack::Attack.throttle('api/token',
                      limit: proc { |req| req.env['rack.attack.api_rate_limit'] || 1_000 },
                      period: 1.hour) do |req|
  next unless req.path.start_with?('/api/')
  next if DawarichSettings.self_hosted?

  api_key = req.params['api_key'] || req.get_header('HTTP_AUTHORIZATION')&.split(' ')&.last
  next if api_key.blank?

  user_plan = Rails.cache.fetch("rack_attack/plan/#{api_key}", expires_in: 2.minutes) do
    User.where(api_key: api_key).pick(:plan)
  end
  next if user_plan.nil?

  req.env['rack.attack.api_rate_limit'] = Rack::Attack.api_rate_limits[user_plan] || 1_000
  api_key
end

# Points creation rate limit: 10,000 req/hr per API key.
# Only applies to cloud instances.
POINTS_CREATION_PATHS = %w[
  /api/v1/points
  /api/v1/owntracks/points
  /api/v1/overland/batches
].freeze

Rack::Attack.throttle('api/points_creation', limit: 10_000, period: 1.hour) do |req|
  next unless req.post? && POINTS_CREATION_PATHS.include?(req.path)
  next if DawarichSettings.self_hosted?

  api_key = req.params['api_key'] || req.get_header('HTTP_AUTHORIZATION')&.split(' ')&.last
  next if api_key.blank?

  "points_creation:#{api_key}"
end

# Heavy-recompute endpoints that fan out into multi-hour Sidekiq work
# (track regeneration, monthly stats, yearly digests, anomaly re-evaluation).
# 5/hr per API key on top of the base api/token throttle, since one
# request can saturate the :default queue for hours.
HEAVY_RECOMPUTE_PATHS = %w[
  /api/v1/recalculations
  /api/v1/points/reapply_anomaly_filter
].freeze

Rack::Attack.throttle('api/heavy_recompute', limit: 5, period: 1.hour) do |req|
  next unless req.post? && HEAVY_RECOMPUTE_PATHS.include?(req.path)
  next if DawarichSettings.self_hosted?

  api_key = req.params['api_key'] || req.get_header('HTTP_AUTHORIZATION')&.split(' ')&.last
  next if api_key.blank?

  "heavy_recompute:#{api_key}"
end

# Login brute-force protection: 5 attempts per email per minute, 20 per IP per minute.
Rack::Attack.throttle('logins/email', limit: 5, period: 1.minute) do |req|
  next unless req.path == '/users/sign_in' && req.post?

  req.params.dig('user', 'email')&.downcase&.strip
end

Rack::Attack.throttle('logins/ip', limit: 20, period: 1.minute) do |req|
  next unless req.path == '/users/sign_in' && req.post?

  req.ip
end

Rack::Attack.throttle('subscriptions/callback', limit: 60, period: 1.minute) do |req|
  next unless req.path == '/api/v1/subscriptions/callback' && req.post?

  req.ip
end

Rack::Attack.throttle('trial/welcome', limit: 30, period: 1.minute) do |req|
  next unless req.path == '/trial/welcome' && req.get?

  req.ip
end

Rack::Attack.throttle('signups/ip_burst', limit: 5, period: 1.minute) do |req|
  next unless req.path == '/users' && req.post?

  req.ip
end

Rack::Attack.throttle('signups/ip_hourly', limit: 20, period: 1.hour) do |req|
  next unless req.path == '/users' && req.post?

  req.ip
end

# Flipper admin UI: 30 req / 5 min per IP. The UI sits behind admin auth, but
# limit hammering so an attacker (or buggy client) can't brute-force or scrape it.
Rack::Attack.throttle('admin/flipper', limit: 30, period: 5.minutes) do |req|
  req.ip if req.path.start_with?('/admin/flipper')
end

Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env['rack.attack.match_data'] || {}
  now = Time.current
  period = match_data[:period] || 3600

  headers = {
    'Content-Type' => 'application/json',
    'Retry-After' => (period - (now.to_i % period)).to_s
  }

  body = {
    error: 'rate_limit_exceeded',
    message: 'API rate limit exceeded. Please wait before making more requests.',
    upgrade_url: "#{MANAGER_URL}/pricing"
  }.to_json

  [429, headers, [body]]
end

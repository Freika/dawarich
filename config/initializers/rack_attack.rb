# frozen_string_literal: true

# Per-plan API rate limiting using rack-attack with Redis backend.
# Self-hosted instances are exempt from rate limiting entirely.
# Cloud plans: Lite = 200 req/hr, Pro = 1,000 req/hr.
# Points creation endpoints: 10,000 req/hr (all plans, including self-hosted).

Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
  url: ENV['REDIS_URL'],
  db: ENV.fetch('RACK_ATTACK_REDIS_DB', '3').to_i # dbs 0-2 are reserved for app caching, sidekiq and ws.
)

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

# Login brute-force protection: 5 attempts per email per minute, 20 per IP per minute.
Rack::Attack.throttle('logins/email', limit: 5, period: 1.minute) do |req|
  next unless req.path == '/users/sign_in' && req.post?

  req.params.dig('user', 'email')&.downcase&.strip
end

Rack::Attack.throttle('logins/ip', limit: 20, period: 1.minute) do |req|
  next unless req.path == '/users/sign_in' && req.post?

  req.ip
end

# Rate-limit OTP challenge attempts: 5 per 15 minutes.
# Protects against brute-forcing a 6-digit TOTP within its validity window.
# Ideally throttle by SHA256(challenge_token); IP-based throttling is a pragmatic
# fallback since the request body isn't easily accessible here.
Rack::Attack.throttle('api/auth/otp_challenge', limit: 5, period: 15.minutes) do |req|
  if req.path == '/api/v1/auth/otp_challenge' && req.post?
    req.ip
  end
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

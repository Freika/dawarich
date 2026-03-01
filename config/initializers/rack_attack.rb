# frozen_string_literal: true

# Per-plan API rate limiting using rack-attack with Redis backend.
# Self-hosted instances are exempt from rate limiting entirely.
# Cloud plans: Lite = 200 req/hr, Pro = 1,000 req/hr.

Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
  url: ENV['REDIS_URL'],
  db: ENV.fetch('RACK_ATTACK_REDIS_DB', 2)
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

  user = Rails.cache.fetch("rack_attack/user/#{api_key}", expires_in: 2.minutes) do
    User.find_by(api_key: api_key)
  end
  next if user.nil?

  req.env['rack.attack.api_rate_limit'] = Rack::Attack.api_rate_limits[user.plan] || 1_000
  api_key
end

Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env['rack.attack.match_data'] || {}
  now = Time.zone.now

  headers = {
    'Content-Type' => 'application/json',
    'Retry-After' => (match_data[:period] - (now.to_i % match_data[:period])).to_s
  }

  body = {
    error: 'rate_limit_exceeded',
    message: 'API rate limit exceeded. Please wait before making more requests.',
    upgrade_url: 'https://dawarich.app/pricing'
  }.to_json

  [429, headers, [body]]
end

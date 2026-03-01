# frozen_string_literal: true

# Per-plan API rate limiting using rack-attack with Redis backend.
# - Self-hosters: no rate limiting
# - Lite: 200 requests/hour
# - Pro: 1,000 requests/hour

Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
  url: ENV['REDIS_URL'],
  db: ENV.fetch('RACK_ATTACK_REDIS_DB', 2)
)

API_RATE_LIMITS = {
  'lite' => 200,
  'pro' => 1_000
}.freeze

Rack::Attack.throttle('api/token',
                      limit: proc { |req| req.env['rack.attack.api_rate_limit'] || 1_000 },
                      period: 1.hour) do |req|
  next unless req.path.start_with?('/api/')

  api_key = req.params['api_key'] || req.get_header('HTTP_AUTHORIZATION')&.split(' ')&.last
  next if api_key.blank?

  user = User.find_by(api_key: api_key)
  next if user.nil? || user.self_hoster?

  req.env['rack.attack.api_rate_limit'] = API_RATE_LIMITS[user.plan] || 1_000
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

# frozen_string_literal: true

# Rate limiting configuration using Rack::Attack
#
# Tiered throttling:
#   - Public/unauthenticated endpoints: throttled by IP
#   - Authenticated API endpoints: throttled by API key
#
# Redis DB 3 is used for rate limit counters (DB 0 = cache, DB 1 = Sidekiq, DB 2 = ActionCable)

Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
  url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'),
  db: ENV.fetch('RAILS_RATE_LIMIT_DB', 3)
)

# --- API key extraction (mirrors ApiController#api_key) ---

extract_api_key = lambda { |req|
  req.params['api_key'] || req.env['HTTP_AUTHORIZATION']&.split(' ')&.last
}

# --- Safelists ---

Rack::Attack.safelist('allow-localhost') do |req|
  %w[127.0.0.1 ::1].include?(req.ip)
end

# --- Public endpoint throttles (by IP) ---

Rack::Attack.throttle('public/health', limit: 60, period: 60) do |req|
  req.ip if req.path == '/api/v1/health' && req.get?
end

Rack::Attack.throttle('public/shared', limit: 30, period: 60) do |req|
  req.ip if req.path.start_with?('/api/v1/maps/hexagons') && req.params['uuid'].present?
end

Rack::Attack.throttle('public/subscription_callback', limit: 10, period: 60) do |req|
  req.ip if req.path == '/api/v1/subscriptions/callback' && req.post?
end

Rack::Attack.throttle('public/login', limit: 10, period: 60) do |req|
  req.ip if req.path == '/users/sign_in' && req.post?
end

# --- Authenticated endpoint throttles (by API key) ---

LOCATION_INGESTION_PATHS = %w[
  /api/v1/overland/batches
  /api/v1/owntracks/points
  /api/v1/points
].freeze

Rack::Attack.throttle('api/location_ingestion', limit: 60, period: 60) do |req|
  extract_api_key.call(req) if req.post? && LOCATION_INGESTION_PATHS.include?(req.path)
end

Rack::Attack.throttle('api/destructive_ops', limit: 10, period: 60) do |req|
  if req.path.start_with?('/api/v1/') && (req.delete? || req.patch? || req.put?) &&
     (req.path.include?('bulk_destroy') || req.path == '/api/v1/settings')
    extract_api_key.call(req)
  end
end

Rack::Attack.throttle('api/general', limit: 600, period: 60) do |req|
  extract_api_key.call(req) if req.path.start_with?('/api/v1/') && extract_api_key.call(req).present?
end

# --- Custom 429 response ---

Rack::Attack.throttled_responder = lambda { |request|
  match_data = request.env['rack.attack.match_data'] || {}
  now = match_data[:epoch_time] || Time.now.to_i
  retry_after = match_data[:period] ? (match_data[:period] - (now % match_data[:period])).to_i : 60

  headers = {
    'Content-Type' => 'application/json',
    'Retry-After' => retry_after.to_s,
    'X-RateLimit-Limit' => (match_data[:limit] || 0).to_s,
    'X-RateLimit-Remaining' => '0',
    'X-RateLimit-Reset' => (now + retry_after).to_s
  }

  body = { error: 'Rate limit exceeded', retry_after: retry_after }.to_json

  [429, headers, [body]]
}

# --- Logging ---

ActiveSupport::Notifications.subscribe('throttle.rack_attack') do |_name, _start, _finish, _id, payload|
  request = payload[:request]
  api_key = extract_api_key.call(request)
  redacted_key = api_key ? "#{api_key[0..7]}..." : nil

  Rails.logger.warn(
    "[Rack::Attack] Throttled #{request.env['rack.attack.matched']} " \
    "#{request.request_method} #{request.path} " \
    "ip=#{request.ip} api_key=#{redacted_key}"
  )
end

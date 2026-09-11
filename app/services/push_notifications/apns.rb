# frozen_string_literal: true

class PushNotifications::Apns
  TOKEN_CACHE = ActiveSupport::Cache::MemoryStore.new
  TOKEN_MUTEX = Mutex.new

  def self.configured?
    %w[APNS_KEY_ID APNS_TEAM_ID APNS_PRIVATE_KEY APNS_TOPIC].all? { |key| ENV[key].present? }
  end

  def deliver(subscription, payload)
    host = subscription.environment == 'development' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com'
    response = HTTPX.with(timeout: { connect_timeout: 5, operation_timeout: 10, request_timeout: 15 }).post(
      "https://#{host}/3/device/#{subscription.push_token}",
      headers: { 'authorization' => "bearer #{authorization}", 'apns-topic' => ENV.fetch('APNS_TOPIC'),
                 'apns-push-type' => 'alert', 'apns-priority' => '10',
                 'apns-expiration' => (Time.current.to_i + payload.fetch(:ttl)).to_s,
                 'apns-collapse-id' => "family-request-#{payload.fetch(:data).fetch(:request_id)}" },
      json: { aps: { alert: payload.slice(:title, :body), sound: payload.fetch(:sound) }, body: payload.fetch(:data) }
    )
    response.raise_for_status if response.is_a?(HTTPX::ErrorResponse)
    return :sent if response.status == 200

    reason = JSON.parse(response.body.to_s)['reason']
    return :unregistered if (response.status == 410 && reason == 'Unregistered') ||
                            (response.status == 400 && reason == 'BadDeviceToken')

    raise Families::PushNotification::DeliveryError, "APNs rejected notification (HTTP #{response.status})"
  end

  private

  def authorization
    # Memory-only caching avoids reissuing a provider JWT for every notification.
    cache_key = Digest::SHA256.hexdigest(%w[APNS_KEY_ID APNS_TEAM_ID APNS_PRIVATE_KEY].map do |key|
      ENV.fetch(key)
    end.join)
    TOKEN_MUTEX.synchronize do
      TOKEN_CACHE.fetch(cache_key, expires_in: 50.minutes) do
        JWT.encode({ iss: ENV.fetch('APNS_TEAM_ID'), iat: Time.current.to_i },
                   OpenSSL::PKey.read(ENV.fetch('APNS_PRIVATE_KEY')), 'ES256', { kid: ENV.fetch('APNS_KEY_ID') })
      end
    end
  end
end

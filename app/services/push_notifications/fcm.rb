# frozen_string_literal: true

require 'net/http'

class PushNotifications::Fcm
  TOKEN_ENDPOINT = 'https://oauth2.googleapis.com/token'
  TOKEN_CACHE = ActiveSupport::Cache::MemoryStore.new
  TOKEN_MUTEX = Mutex.new

  def self.configured?
    ENV['FCM_SERVICE_ACCOUNT_JSON'].present?
  end

  def deliver(subscription, payload)
    credentials = JSON.parse(ENV.fetch('FCM_SERVICE_ACCOUNT_JSON'))
    project = credentials.fetch('project_id')
    unless project.match?(/\A[a-zA-Z0-9-]+\z/)
      raise Families::PushNotification::DeliveryError, 'Invalid Firebase project configuration'
    end

    message = {
      token: subscription.push_token,
      notification: payload.slice(:title, :body),
      data: { body: payload.fetch(:data).to_json },
      android: { priority: 'HIGH', ttl: "#{payload.fetch(:ttl)}s",
                 notification: { channel_id: 'family-requests', sound: 'default',
                                 tag: "family-request-#{payload.fetch(:data).fetch(:request_id)}" } }
    }
    response = post(URI("https://fcm.googleapis.com/v1/projects/#{project}/messages:send"),
                    { message: message }, authorization: access_token(credentials))
    return :sent if response.is_a?(Net::HTTPSuccess)

    errors = JSON.parse(response.body).dig('error', 'details') || []
    if response.code == '404' && errors.any? do |error|
         error['@type'] == 'type.googleapis.com/google.firebase.fcm.v1.FcmError' && error['errorCode'] == 'UNREGISTERED'
       end
      return :unregistered
    end

    raise Families::PushNotification::DeliveryError, "FCM rejected notification (HTTP #{response.code})"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET, OpenSSL::SSL::SSLError
    raise Families::PushNotification::DeliveryError, 'FCM connection failed', cause: nil
  end

  private

  def access_token(credentials)
    cache_key = Digest::SHA256.hexdigest(ENV.fetch('FCM_SERVICE_ACCOUNT_JSON'))
    TOKEN_MUTEX.synchronize do
      TOKEN_CACHE.fetch(cache_key, expires_in: 50.minutes) do
        now = Time.current.to_i
        assertion = JWT.encode({ iss: credentials.fetch('client_email'),
                                 scope: 'https://www.googleapis.com/auth/firebase.messaging',
                                 aud: TOKEN_ENDPOINT, iat: now, exp: now + 3600 },
                               OpenSSL::PKey.read(credentials.fetch('private_key')), 'RS256')
        uri = URI(TOKEN_ENDPOINT)
        request = Net::HTTP::Post.new(uri)
        request.set_form_data(grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: assertion)
        response = perform_request(uri, request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Families::PushNotification::DeliveryError, "FCM authorization failed (HTTP #{response.code})"
        end

        JSON.parse(response.body).fetch('access_token')
      end
    end
  end

  def post(uri, payload, authorization:)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{authorization}"
    request.body = payload.to_json
    perform_request(uri, request)
  end

  def perform_request(uri, request)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10, write_timeout: 10) do |http|
      http.request(request)
    end
  end
end

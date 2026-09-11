# frozen_string_literal: true

require 'net/http'

class Families::PushNotification
  class DeliveryError < StandardError; end

  def self.deliver(subscription, payload)
    provider = subscription.provider == 'apns' ? PushNotifications::Apns : PushNotifications::Fcm
    provider.new.deliver(subscription, payload)
  rescue HTTPX::Error, JSON::ParserError, KeyError, OpenSSL::PKey::PKeyError, JWT::EncodeError,
         IOError, SystemCallError, Timeout::Error, Net::ProtocolError, OpenSSL::SSL::SSLError
    # Provider exceptions can include the request URI (device token) or credentials.
    raise DeliveryError, 'Native push delivery failed', cause: nil
  end
end

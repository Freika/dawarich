# frozen_string_literal: true

module VideoExports
  class CallbackToken
    EXPIRY = 24.hours

    def self.generate(video_export_id)
      data = "#{video_export_id}:#{Time.current.to_i}"
      digest = OpenSSL::HMAC.hexdigest('SHA256', secret_key, data)
      Base64.urlsafe_encode64("#{data}:#{digest}")
    end

    def self.verify(token, video_export_id)
      decoded = Base64.urlsafe_decode64(token)
      parts = decoded.split(':')
      return false unless parts.length == 3

      token_export_id, timestamp, digest = parts
      return false unless token_export_id.to_i == video_export_id

      expected_data = "#{token_export_id}:#{timestamp}"
      expected_digest = OpenSSL::HMAC.hexdigest('SHA256', secret_key, expected_data)
      return false unless ActiveSupport::SecurityUtils.secure_compare(digest, expected_digest)

      Time.zone.at(timestamp.to_i) > EXPIRY.ago
    rescue ArgumentError
      false
    end

    def self.secret_key
      Rails.application.secret_key_base
    end

    private_class_method :secret_key
  end
end

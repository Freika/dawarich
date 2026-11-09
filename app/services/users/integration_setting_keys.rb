# frozen_string_literal: true

module Users
  # Which user settings belong to an integration connection (Immich,
  # Photoprism, AirTrail, TeslaMate), and which of those are secrets.
  module IntegrationSettingKeys
    PREFIXES = %w[immich_ photoprism_ airtrail_ teslamate_].freeze

    # Never written to a user data archive.
    SECRETS = %w[
      immich_api_key photoprism_api_key airtrail_api_key teslamate_password teslamate_api_token
    ].freeze

    # URL, credentials, flags, connection status and sync state alike.
    def self.connection_key?(key)
      key.to_s.start_with?(*PREFIXES)
    end

    # A self-hosted integration URL may carry basic-auth credentials
    # (http://user:pass@host). They are a secret like the API key.
    def self.without_credentials(url)
      return url unless url.is_a?(String) && url.include?('@')

      uri = URI.parse(url)
      # In this order: URI refuses a password without a user.
      uri.password = nil
      uri.user = nil
      uri.to_s
    rescue URI::InvalidURIError
      # Unparsable, but still not allowed to carry credentials out.
      url.sub(%r{//[^/]*@}, '//')
    end

    # Settings safe to write to an archive: no secret keys, no credentials in URLs.
    def self.redact(settings)
      settings.except(*SECRETS).to_h do |key, value|
        [key, connection_key?(key) && key.to_s.end_with?('_url') ? without_credentials(value) : value]
      end
    end
  end
end

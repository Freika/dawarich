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
      # Unparsable (or saved without a scheme), but still not allowed to carry
      # credentials out: drop everything up to the last @ of the authority.
      url.sub(%r{\A([^/?#]*//)?[^/?#]*@}, '\1')
    end

    # An API write that changes an integration URL without sending the secret
    # along forgets the stored secret: otherwise the next request would send
    # it to the new host. A URL equal to what the API returns (the stored URL
    # without credentials) is not a change and is left out of the write.
    def self.guard_url_changes(incoming, stored)
      incoming = incoming.to_h.stringify_keys
      incoming.keys.select { |key| connection_key?(key) && key.end_with?('_url') }.each do |url_key|
        next if incoming[url_key] == stored[url_key]
        next incoming.delete(url_key) if incoming[url_key] == without_credentials(stored[url_key])

        prefix = PREFIXES.find { |candidate| url_key.start_with?(candidate) }
        secrets = SECRETS.select { |secret| secret.start_with?(prefix) }
        next if secrets.any? { |secret| incoming[secret].present? }

        secrets.each { |secret| incoming[secret] = nil }
        incoming["#{prefix}connection_status"] = nil
      end
      incoming
    end

    # Settings safe to write to an archive: no secret keys, no credentials in URLs.
    def self.redact(settings)
      settings.except(*SECRETS).to_h do |key, value|
        [key, connection_key?(key) && key.to_s.end_with?('_url') ? without_credentials(value) : value]
      end
    end
  end
end

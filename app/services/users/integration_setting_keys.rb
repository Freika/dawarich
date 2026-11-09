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
  end
end

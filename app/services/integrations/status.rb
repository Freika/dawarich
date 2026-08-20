# frozen_string_literal: true

module Integrations
  class Status
    PHOTO_SERVICES = %w[immich photoprism airtrail].freeze
    SERVICES = (%w[geocoding] + PHOTO_SERVICES).freeze

    def self.for(user)
      new(user)
    end

    def initialize(user)
      @user = user
    end

    def configured?(service)
      service = service.to_s

      if service == 'geocoding'
        geocoding_config.enabled?
      else
        settings["#{service}_url"].present? && settings["#{service}_api_key"].present?
      end
    end

    def status(service)
      service = service.to_s
      return unless configured?(service)

      if service == 'geocoding'
        geocoding_status
      else
        normalize(settings["#{service}_connection_status"])
      end
    end

    private

    attr_reader :user

    def settings
      @settings ||= user.safe_settings.settings
    end

    def geocoding_config
      @geocoding_config ||= Geocoding::Config.for(user)
    end

    def geocoding_status
      return if geocoding_config.env_managed?

      setting = user.service_settings.service_geocoding.find_by(active: true)
      normalize(setting&.config&.fetch('connection_status', nil))
    end

    def normalize(value)
      case value
      when 'ok' then :connected
      when 'failed' then :failed
      end
    end
  end
end

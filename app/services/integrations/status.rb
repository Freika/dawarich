# frozen_string_literal: true

module Integrations
  class Status
    EXTERNAL_SERVICES = %w[immich photoprism airtrail teslamate trek].freeze
    SERVICES = (%w[geocoding] + EXTERNAL_SERVICES).freeze

    def self.for(user)
      new(user)
    end

    def initialize(user)
      @user = user
      @status = {}
    end

    def configured?(service)
      service = service.to_s

      case service
      when 'geocoding'
        geocoding_config.enabled?
      when 'trek'
        user.trip_sources.active.where(provider: 'trek').exists?
      when 'teslamate'
        settings['teslamate_url'].present?
      else
        settings["#{service}_url"].present? && settings["#{service}_api_key"].present?
      end
    end

    def status(service)
      service = service.to_s
      return @status[service] if @status.key?(service)

      @status[service] = resolve_status(service)
    end

    private

    attr_reader :user

    def resolve_status(service)
      return unless configured?(service)

      if service == 'geocoding'
        geocoding_status
      elsif service == 'trek'
        trek_status
      else
        normalize(settings["#{service}_connection_status"])
      end
    end

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

    def trek_status
      source = user.trip_sources.where(provider: 'trek').order(updated_at: :desc).first
      return unless source

      source.active? ? :connected : :failed
    end

    def normalize(value)
      case value
      when 'ok' then :connected
      when 'failed' then :failed
      end
    end
  end
end

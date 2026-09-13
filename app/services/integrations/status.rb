# frozen_string_literal: true

module Integrations
  class Status
    SERVICES = %w[immich photoprism airtrail].freeze

    def self.for(user)
      new(user)
    end

    def initialize(user)
      @user = user
      @status = {}
    end

    def configured?(service)
      service = service.to_s

      settings["#{service}_url"].present? && settings["#{service}_api_key"].present?
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

      normalize(settings["#{service}_connection_status"])
    end

    def settings
      @settings ||= user.safe_settings.settings
    end

    def normalize(value)
      case value
      when 'ok' then :connected
      when 'failed' then :failed
      end
    end
  end
end

# frozen_string_literal: true

module AirTrail
  class ConnectionTester
    def initialize(url, api_key, skip_ssl_verification: false)
      @url = url
      @api_key = api_key
      @skip_ssl_verification = skip_ssl_verification
    end

    def call
      if @url.blank?
        return { success: false,
error: I18n.t('services.air_trail.connection_tester.airtrail_url_is_missing') }
      end
      if @api_key.blank?
        return { success: false,
error: I18n.t('services.air_trail.connection_tester.airtrail_api_key_is_missing') }
      end

      AirTrail::Client.new(@url, @api_key, skip_ssl_verification: @skip_ssl_verification).flights
      { success: true, message: I18n.t('services.air_trail.connection_tester.airtrail_connection_verified') }
    rescue AirTrail::Client::Error => e
      { success: false,
error: I18n.t('services.air_trail.connection_tester.airtrail_connection_failed_message', message: e.message) }
    end
  end
end

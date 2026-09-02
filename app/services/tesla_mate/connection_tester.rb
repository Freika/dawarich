# frozen_string_literal: true

module TeslaMate
  class ConnectionTester
    def initialize(url, username: nil, password: nil, api_token: nil, skip_ssl_verification: false)
      @url = url
      @client_options = {
        username: username,
        password: password,
        api_token: api_token,
        skip_ssl_verification: skip_ssl_verification
      }
    end

    def call
      if @url.blank?
        return { success: false,
                 error: I18n.t('services.tesla_mate.connection_tester.teslamate_url_is_missing') }
      end

      TeslaMate::Client.new(@url, **@client_options).cars
      { success: true,
        message: I18n.t('services.tesla_mate.connection_tester.teslamate_connection_verified') }
    rescue TeslaMate::Client::Error => e
      { success: false,
        error: I18n.t('services.tesla_mate.connection_tester.teslamate_connection_failed_message',
                      message: e.message) }
    end
  end
end

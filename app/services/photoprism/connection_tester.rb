# frozen_string_literal: true

class Photoprism::ConnectionTester
  include SslConfigurable

  attr_reader :url, :api_key, :skip_ssl_verification

  def initialize(url, api_key, skip_ssl_verification: false)
    @url = url
    @api_key = api_key
    @skip_ssl_verification = skip_ssl_verification
  end

  def call
    if url.blank?
      return { success: false,
error: I18n.t('services.photoprism.connection_tester.photoprism_url_is_missing') }
    end
    if api_key.blank?
      return { success: false,
error: I18n.t('services.photoprism.connection_tester.photoprism_api_key_is_missing') }
    end

    test_connection
  rescue *Photos::ConnectionErrors::HANDLED => e
    { success: false,
error: I18n.t('services.photoprism.connection_tester.photoprism_connection_failed_message', message: e.message) }
  end

  private

  def test_connection
    response = HTTParty.get(
      "#{url}/api/v1/photos",
      http_options_with_ssl_flag(
        skip_ssl_verification, {
          headers: {
            'Authorization' => "Bearer #{api_key}",
            'accept' => 'application/json',
            'Content-Type' => 'application/json'
          },
          query: { count: 1, public: true },
          timeout: 10
        }
      )
    )

    if response.success?
      return { success: true,
message: I18n.t('services.photoprism.connection_tester.photoprism_connection_verified') }
    end

    { success: false,
error: I18n.t('services.photoprism.connection_tester.photoprism_connection_failed_code', code: response.code) }
  end
end

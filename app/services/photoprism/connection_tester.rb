# frozen_string_literal: true

class Photoprism::ConnectionTester
  attr_reader :url, :api_key, :skip_ssl_verification

  def initialize(url, api_key, skip_ssl_verification: false)
    @url = url
    @api_key = api_key
    @skip_ssl_verification = skip_ssl_verification
  end

  def call
    if url.blank?
      return { success: false, reason: 'missing_fields',
error: I18n.t('services.photoprism.connection_tester.photoprism_url_is_missing') }
    end
    if api_key.blank?
      return { success: false, reason: 'missing_fields',
error: I18n.t('services.photoprism.connection_tester.photoprism_api_key_is_missing') }
    end

    test_connection
  rescue *Photos::ConnectionErrors::HANDLED => e
    { success: false, reason: Photos::ConnectionErrors.certificate?(e) ? 'certificate' : 'unreachable',
error: I18n.t('services.photoprism.connection_tester.photoprism_connection_failed_message', message: e.message) }
  end

  private

  def test_connection
    response = Integrations::Transport.request(
      :get, "#{url}/api/v1/photos",
      headers: { 'Authorization' => "Bearer #{api_key}", 'accept' => 'application/json',
                 'Content-Type' => 'application/json' },
      query: { count: 1, public: true },
      skip_ssl_verification:
    )

    if response.success?
      return { success: true,
message: I18n.t('services.photoprism.connection_tester.photoprism_connection_verified') }
    end

    { success: false, reason: response.code.to_i.in?([401, 403]) ? 'credentials' : 'check_settings',
error: I18n.t('services.photoprism.connection_tester.photoprism_connection_failed_code', code: response.code) }
  end
end

# frozen_string_literal: true

class Immich::ConnectionTester
  include SslConfigurable

  attr_reader :url, :api_key, :skip_ssl_verification

  def initialize(url, api_key, skip_ssl_verification: false)
    @url = url
    @api_key = api_key
    @skip_ssl_verification = skip_ssl_verification
  end

  def call
    return { success: false, error: I18n.t('services.immich.connection_tester.immich_url_is_missing') } if url.blank?
    if api_key.blank?
      return { success: false,
error: I18n.t('services.immich.connection_tester.immich_api_key_is_missing') }
    end

    test_connection
  rescue *Photos::ConnectionErrors::HANDLED => e
    { success: false,
error: I18n.t('services.immich.connection_tester.immich_connection_failed_message', message: e.message) }
  end

  private

  def test_connection
    response = search_metadata
    unless response.success?
      return { success: false,
error: I18n.t('services.immich.connection_tester.immich_connection_failed_code',
              code: response.code) }
    end

    asset_id = extract_asset_id(response.body)
    if asset_id.blank?
      return { success: true,
message: I18n.t('services.immich.connection_tester.immich_connection_verified') }
    end

    test_thumbnail_access(asset_id)
  end

  def search_metadata
    HTTParty.post(
      "#{url}/api/search/metadata",
      http_options_with_ssl_flag(
        skip_ssl_verification, {
          headers: {
            'x-api-key' => api_key,
            'accept' => 'application/json',
            'Content-Type' => 'application/json'
          },
          body: {
            takenAfter: Time.current.beginning_of_day.iso8601,
            size: 1,
            page: 1,
            order: 'asc',
            withExif: true
          }.to_json,
        timeout: 10
        }
      )
    )
  end

  def test_thumbnail_access(asset_id)
    response = HTTParty.get(
      "#{url}/api/assets/#{asset_id}/thumbnail?size=preview",
      http_options_with_ssl_flag(skip_ssl_verification, {
                                   headers: { 'x-api-key' => api_key, 'accept' => 'application/octet-stream' },
        timeout: 10
                                 })
    )

    if response.success?
      return { success: true,
message: I18n.t('services.immich.connection_tester.immich_connection_verified') }
    end

    if missing_asset_view_permission?(response)
      return { success: false,
error: I18n.t('services.immich.connection_tester.immich_api_key_missing_permission_asset_view') }
    end

    { success: false,
error: I18n.t('services.immich.connection_tester.immich_thumbnail_check_failed_code', code: response.code) }
  end

  def extract_asset_id(body)
    result = Immich::ResponseValidator.validate_and_parse_body(body)
    return nil unless result[:success]

    result[:data].dig('assets', 'items', 0, 'id')
  end

  def missing_asset_view_permission?(response)
    return false unless response.code.to_i == 403

    result = Immich::ResponseValidator.validate_and_parse_body(response.body)
    return false unless result[:success]

    result[:data]['message']&.include?('asset.view') || false
  end
end

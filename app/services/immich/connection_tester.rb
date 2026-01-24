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
    return { success: false, error: 'Immich URL is missing' } if url.blank?
    return { success: false, error: 'Immich API key is missing' } if api_key.blank?

    test_connection
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError => e
    { success: false, error: "Immich connection failed: #{e.message}" }
  end

  private

  def test_connection
    response = search_metadata
    return { success: false, error: "Immich connection failed: #{response.code}" } unless response.success?

    asset_id = extract_asset_id(response.body)
    return { success: true, message: 'Immich connection verified' } if asset_id.blank?

    test_thumbnail_access(asset_id)
  end

  # rubocop:disable Metrics/MethodLength
  def search_metadata
    HTTParty.post(
      "#{url}/api/search/metadata",
      http_options_with_ssl_flag(skip_ssl_verification, {
        headers: { 'x-api-key' => api_key, 'accept' => 'application/json' },
        body: {
          takenAfter: Time.current.beginning_of_day.iso8601,
          size: 1,
          page: 1,
          order: 'asc',
          withExif: true
        },
        timeout: 10
      })
    )
  end
  # rubocop:enable Metrics/MethodLength

  def test_thumbnail_access(asset_id)
    response = HTTParty.get(
      "#{url}/api/assets/#{asset_id}/thumbnail?size=preview",
      http_options_with_ssl_flag(skip_ssl_verification, {
        headers: { 'x-api-key' => api_key, 'accept' => 'application/octet-stream' },
        timeout: 10
      })
    )

    return { success: true, message: 'Immich connection verified' } if response.success?

    if missing_asset_view_permission?(response)
      return { success: false, error: 'Immich API key missing permission: asset.view' }
    end

    { success: false, error: "Immich thumbnail check failed: #{response.code}" }
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

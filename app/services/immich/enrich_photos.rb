# frozen_string_literal: true

class Immich::EnrichPhotos
  include SslConfigurable

  attr_reader :user, :assets

  def initialize(user, assets)
    @user = user
    @assets = assets
  end

  def call
    return error_result('Immich URL is missing') if user.safe_settings.immich_url.blank?
    return error_result('Immich API key is missing') if user.safe_settings.immich_api_key.blank?
    return { enriched: 0, failed: 0, errors: [] } if assets.empty?

    enriched = 0
    failed = 0
    errors = []

    assets.each do |asset|
      result = update_asset(asset)

      if result[:success]
        enriched += 1
      else
        failed += 1
        errors << { immich_asset_id: asset['immich_asset_id'], error: result[:error] }
      end
    end

    { enriched:, failed:, errors: }
  end

  private

  def update_asset(asset)
    options = {
      headers:,
      body: { latitude: asset['latitude'], longitude: asset['longitude'] }.to_json,
      timeout: 10
    }

    response = HTTParty.put(
      "#{immich_url}/api/assets/#{asset['immich_asset_id']}",
      http_options_with_ssl(user, :immich, options)
    )

    if response.success?
      { success: true }
    else
      { success: false, error: "HTTP #{response.code}: #{response.message}" }
    end
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    { success: false, error: e.message }
  end

  def immich_url
    user.safe_settings.immich_url
  end

  def headers
    {
      'x-api-key' => user.safe_settings.immich_api_key,
      'accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  def error_result(message)
    { error: message, enriched: 0, failed: 0, errors: [] }
  end
end

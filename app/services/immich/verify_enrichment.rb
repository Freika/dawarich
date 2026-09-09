# frozen_string_literal: true

class Immich::VerifyEnrichment
  include SslConfigurable

  def initialize(user, assets)
    @user = user
    @assets = assets
  end

  def call
    @assets.partition { |asset| confirmed?(asset) }
  end

  private

  def confirmed?(asset)
    headers = { 'x-api-key' => @user.safe_settings.immich_api_key, 'accept' => 'application/json' }
    response = HTTParty.get(
      "#{@user.safe_settings.immich_url}/api/assets/#{ERB::Util.url_encode(asset['immich_asset_id'])}",
      http_options_with_ssl(@user, :immich, headers:, timeout: 5)
    )
    return false unless response.success?

    data = JSON.parse(response.body)
    exif = data.is_a?(Hash) && data['exifInfo']
    return false unless exif.is_a?(Hash)

    %w[latitude longitude].all? do |coordinate|
      actual = Float(exif[coordinate], exception: false)
      expected = Float(asset[coordinate], exception: false)
      actual&.finite? && expected&.finite? && (actual - expected).abs <= 0.00001
    end
  rescue *Photos::ConnectionErrors::HANDLED, JSON::ParserError
    false
  end
end

# frozen_string_literal: true

class Immich::Albums
  include SslConfigurable

  CACHE_TTL = 15.minutes

  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    cached_albums = Rails.cache.read(cache_key)
    return cached_albums if cached_albums.present?

    result = fetch_albums
    return [] unless result[:success]

    albums = Array(result[:data])
      .select { |album| album.is_a?(Hash) }
      .sort_by { |album| album['albumName'].to_s.downcase }

    Rails.cache.write(cache_key, albums, expires_in: CACHE_TTL)

    albums
  end

  private

  def fetch_albums
    response = HTTParty.get(
      "#{immich_url}/api/albums",
      http_options_with_ssl(
        user,
        :immich,
        {
          headers: {
            'x-api-key' => user.safe_settings.immich_api_key,
            'accept' => 'application/json'
          },
          timeout: 10
        }
      )
    )

    result = Immich::ResponseValidator.validate_and_parse(response)

    unless result[:success]
      Rails.logger.error("Immich album request failed: #{result[:error]}")
    end

    result
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Immich album request failed: #{e.message}")

    {
      success: false,
      error: e.message
    }
  end

  def immich_url
    user.safe_settings.immich_url.to_s.sub(%r{/$}, '')
  end

  def cache_key
    "immich-albums:user:#{user.id}"
  end
end

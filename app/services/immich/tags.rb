# frozen_string_literal: true

class Immich::Tags
  include SslConfigurable

  CACHE_TTL = 15.minutes

  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    cached_tags = Rails.cache.read(cache_key)
    return cached_tags if cached_tags.present?

    result = fetch_tags
    return {} unless result[:success]

    tags = result[:data].index_by { |tag| tag['value'] }

    Rails.cache.write(cache_key, tags, expires_in: CACHE_TTL)

    tags
  end

  private

  def fetch_tags
    response = HTTParty.get(
      "#{immich_url}/api/tags",
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
      Rails.logger.error("Immich tag request failed: #{result[:error]}")
    end

    result
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Immich tag request failed: #{e.message}")

    {
      success: false,
      error: e.message
    }
  end

  def immich_url
    user.safe_settings.immich_url.to_s.sub(%r{/$}, '')
  end

  def cache_key
    "immich-tags:user:#{user.id}"
  end
end

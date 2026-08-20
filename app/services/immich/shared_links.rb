# frozen_string_literal: true

class Immich::SharedLinks
  include SslConfigurable

  CACHE_TTL = 15.minutes

  def initialize(user)
    @user = user
  end

  def call
    cached_links = Rails.cache.read(cache_key)
    return cached_links unless cached_links.nil?

    result = fetch_shared_links
    return [] unless result[:success]

    links = Array(result[:data]).select { |link| usable?(link) }
    Rails.cache.write(cache_key, links, expires_in: CACHE_TTL)
    links
  end

  private

  attr_reader :user

  def fetch_shared_links
    response = HTTParty.get(
      "#{immich_url}/api/shared-links",
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
    Rails.logger.error("Immich shared-link request failed: #{result[:error]}") unless result[:success]
    result
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Immich shared-link request failed: #{e.message}")
    { success: false, error: e.message }
  end

  def usable?(link)
    link.is_a?(Hash) &&
      link['id'].present? &&
      link['slug'].present? &&
      link['album'].is_a?(Hash) &&
      link.dig('album', 'id').present?
  end

  def immich_url
    user.safe_settings.immich_url.to_s.sub(%r{/$}, '')
  end

  def cache_key
    "immich-shared-links:user:#{user.id}"
  end
end

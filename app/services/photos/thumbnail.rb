# frozen_string_literal: true

class Photos::Thumbnail
  include SslConfigurable

  SUPPORTED_SOURCES = %w[immich photoprism google_photos].freeze

  def initialize(user, source, id)
    @user = user
    @source = source
    @id = id
  end

  def call
    raise ArgumentError, 'Photo source cannot be nil' if source.nil?
    unsupported_source_error unless SUPPORTED_SOURCES.include?(source)

    # Google Photos thumbnails are publicly accessible via the baseUrl
    # No authentication needed - just fetch directly
    return fetch_google_photos_thumbnail if source == 'google_photos'

    HTTParty.get(
      request_url,
      http_options_with_ssl(@user, source_type, {
        headers: headers
      })
    )
  end

  private

  attr_reader :user, :source, :id

  def source_url
    user.safe_settings.public_send("#{source}_url")
  end

  def source_api_key
    user.safe_settings.public_send("#{source}_api_key")
  end

  def source_path
    case source
    when 'immich'
      "/api/assets/#{id}/thumbnail?size=preview"
    when 'photoprism'
      preview_token = Rails.cache.read("#{Photoprism::CachePreviewToken::TOKEN_CACHE_KEY}_#{user.id}")
      "/api/v1/t/#{id}/#{preview_token}/tile_500"
    end
  end

  def request_url
    "#{source_url}#{source_path}"
  end

  def headers
    request_headers = {
      'accept' => 'application/octet-stream'
    }

    request_headers['X-Api-Key'] = source_api_key if source == 'immich'

    request_headers
  end

  def unsupported_source_error
    raise ArgumentError, "Unsupported source: #{source}"
  end

  def source_type
    source == 'immich' ? :immich : :photoprism
  end

  def fetch_google_photos_thumbnail
    # For Google Photos, the id IS the baseUrl
    # Append size parameters for thumbnail (500x500 max dimension)
    thumbnail_url = "#{id}=w500-h500"

    HTTParty.get(
      thumbnail_url,
      headers: { 'Accept' => 'image/*' },
      timeout: 10
    )
  end
end

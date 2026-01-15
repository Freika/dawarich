# frozen_string_literal: true

class Photos::Thumbnail
  include SslConfigurable

  SUPPORTED_SOURCES = %w[immich photoprism].freeze

  def initialize(user, source, id)
    @user = user
    @source = source
    @id = id
  end

  def call
    raise ArgumentError, 'Photo source cannot be nil' if source.nil?
    unsupported_source_error unless SUPPORTED_SOURCES.include?(source)

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
end

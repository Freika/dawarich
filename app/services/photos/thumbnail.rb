# frozen_string_literal: true

class Photos::Thumbnail
  def initialize(user, source, id)
    @user = user
    @source = source
    @id = id
  end

  def call
    fetch_thumbnail_from_source
  end

  private

  attr_reader :user, :source, :id

  def source_url
    user.settings["#{source}_url"]
  end

  def source_api_key
    user.settings["#{source}_api_key"]
  end

  def source_path
    case source
    when 'immich'
      "/api/assets/#{id}/thumbnail?size=preview"
    when 'photoprism'
      preview_token = Rails.cache.read("#{Photoprism::CachePreviewToken::TOKEN_CACHE_KEY}_#{user.id}")
      "/api/v1/t/#{id}/#{preview_token}/tile_500"
    else
      raise "Unsupported source: #{source}"
    end
  end

  def headers
    request_headers = {
      'accept' => 'application/octet-stream'
    }

    request_headers['X-Api-Key'] = source_api_key if source == 'immich'

    request_headers
  end

  def fetch_thumbnail_from_source
    url = "#{source_url}#{source_path}"
    a = HTTParty.get(url, headers: headers)
    pp url
    a
  end
end

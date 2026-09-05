# frozen_string_literal: true

class CheckAppVersion
  VERSION_CACHE_KEY = 'dawarich/app-version-check'

  def initialize
    @repo_url = 'https://api.github.com/repos/Freika/dawarich/tags'
  end

  def call
    return false if Rails.env.production?

    cached_version = Rails.cache.read(VERSION_CACHE_KEY)
    cached_version.present? && Gem::Version.new(cached_version) > Gem::Version.new(APP_VERSION)
  rescue StandardError
    false
  end

  def refresh
    return false if Rails.env.production?

    uri = URI.parse(@repo_url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5,
                                                max_retries: 0) do |http|
      http.get(uri.request_uri)
    end
    return false unless response.is_a?(Net::HTTPSuccess)

    versions = JSON.parse(response.body)
    release_version = versions.find { |version| version['name'].match?(/^\d+\.\d+\.\d+$/) }
    Rails.cache.write(VERSION_CACHE_KEY, release_version ? release_version['name'] : APP_VERSION, expires_in: 6.hours)
  rescue StandardError
    false
  end
end

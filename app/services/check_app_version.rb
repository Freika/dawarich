# frozen_string_literal: true

class CheckAppVersion
  VERSION_CACHE_KEY = 'dawarich/app-version-check'

  def initialize
    @repo_url = 'https://api.github.com/repos/Freika/dawarich/tags'
  end

  def call
    return false if Rails.env.production?

    [Rails.cache.read(VERSION_CACHE_KEY), PhoenixAppVersion.fresh_latest].compact_blank.any? do |version|
      Gem::Version.new(version) > Gem::Version.new(APP_VERSION)
    end
  rescue StandardError
    false
  end

  def refresh
    latest = fetch_latest
    latest ? store(latest) : false
  end

  def fetch_latest
    return if Rails.env.production?

    uri = URI.parse(@repo_url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5,
                                                max_retries: 0) do |http|
      http.get(uri.request_uri)
    end
    return unless response.is_a?(Net::HTTPSuccess)

    versions = JSON.parse(response.body)
    release_version = versions.find { |version| version['name'].match?(/^\d+\.\d+\.\d+$/) }
    release_version ? release_version['name'] : APP_VERSION
  rescue StandardError
    nil
  end

  def store(version)
    Rails.cache.write(VERSION_CACHE_KEY, version, expires_in: 6.hours)
  rescue StandardError
    false
  end
end

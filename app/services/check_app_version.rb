# frozen_string_literal: true

class CheckAppVersion
  VERSION_CACHE_KEY = 'dawarich/app-version-check'

  def initialize
    @repo_url = 'https://api.github.com/repos/Freika/dawarich/tags'
  end

  def call
    return false if Rails.env.production?

    latest_version != APP_VERSION
  rescue StandardError
    false
  end

  private

  def latest_version
    Rails.cache.fetch(VERSION_CACHE_KEY, expires_in: 6.hours) do
      versions = JSON.parse(Net::HTTP.get(URI.parse(@repo_url)))
      # Find first version that contains only numbers and dots
      release_version = versions.find { |v| v['name'].match?(/^\d+\.\d+\.\d+$/) }
      release_version ? release_version['name'] : APP_VERSION
    end
  end
end

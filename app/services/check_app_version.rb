# frozen_string_literal: true

class CheckAppVersion
  VERSION_CACHE_KEY = 'dawarich/app-version-check'

  def initialize
    @repo_url = 'https://api.github.com/repos/Freika/dawarich/tags'
  end

  def call
    latest_version != APP_VERSION
  rescue StandardError
    false
  end

  private

  def latest_version
    Rails.cache.fetch(VERSION_CACHE_KEY, expires_in: 6.hours) do
      JSON.parse(Net::HTTP.get(URI.parse(@repo_url)))[0]['name']
    end
  end
end

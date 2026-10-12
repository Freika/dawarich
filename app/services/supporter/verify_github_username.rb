# frozen_string_literal: true

module Supporter
  class VerifyGithubUsername
    CACHE_TTL = 24.hours
    SUPPORTER_VERIFICATION_URL = 'https://verify.dawarich.app/api/v1/verify'

    attr_reader :username

    def initialize(username)
      @username = username&.strip&.downcase
    end

    def call
      return { supporter: false } if username.blank?

      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        fetch_supporter_status
      end
    end

    def cache_key
      "dawarich/supporter_gh:#{username}"
    end

    private

    def fetch_supporter_status
      response = HTTParty.get(
        "#{SUPPORTER_VERIFICATION_URL}?github_username=#{CGI.escape(username)}",
        timeout: 5,
        headers: { 'X-Dawarich-Version' => APP_VERSION }
      )

      response.success? ? response.parsed_response.symbolize_keys : { supporter: false }
    rescue StandardError => e
      Rails.logger.warn("Supporter github verification failed: #{e.message}")
      { supporter: false }
    end
  end
end

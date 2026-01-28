# frozen_string_literal: true

module Supporter
  class VerifyEmail
    CACHE_TTL = 24.hours
    SUPPORTER_VERIFICATION_URL = 'https://verify.dawarich.app/api/v1/verify'

    attr_reader :email

    def initialize(email)
      @email = email&.downcase&.strip
    end

    def call
      return { supporter: false } if email.blank?

      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        fetch_supporter_status
      end
    end

    def cache_key
      "dawarich/supporter:#{email_hash}"
    end

    private

    def fetch_supporter_status
      response = HTTParty.get(
        "#{SUPPORTER_VERIFICATION_URL}?email_hash=#{email_hash}",
        timeout: 5,
        headers: { 'X-Dawarich-Version' => APP_VERSION }
      )

      response.success? ? response.parsed_response.symbolize_keys : { supporter: false }
    rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
      Rails.logger.warn("Supporter verification failed: #{e.message}")
      { supporter: false }
    end

    def email_hash
      Digest::SHA256.hexdigest(email)
    end
  end
end

# frozen_string_literal: true

class Photoprism::ConnectionTester
  attr_reader :url, :api_key, :skip_ssl_verification

  def initialize(url, api_key, skip_ssl_verification: false)
    @url = url
    @api_key = api_key
    @skip_ssl_verification = skip_ssl_verification
  end

  def call
    return { success: false, error: 'Photoprism URL is missing' } if url.blank?
    return { success: false, error: 'Photoprism API key is missing' } if api_key.blank?

    test_connection
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError => e
    { success: false, error: "Photoprism connection failed: #{e.message}" }
  end

  private

  def test_connection
    response = HTTParty.get(
      "#{url}/api/v1/photos",
      http_options_with_ssl(
        {
          headers: { 'Authorization' => "Bearer #{api_key}", 'accept' => 'application/json' },
          query: { count: 1, public: true },
          timeout: 10
        }
      )
    )

    return { success: true, message: 'Photoprism connection verified' } if response.success?

    { success: false, error: "Photoprism connection failed: #{response.code}" }
  end

  def http_options_with_ssl(base_options = {})
    base_options.merge(verify: !skip_ssl_verification)
  end
end

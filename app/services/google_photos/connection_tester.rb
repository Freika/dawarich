# frozen_string_literal: true

module GooglePhotos
  class ConnectionTester
    GOOGLE_PHOTOS_API_URL = 'https://photoslibrary.googleapis.com/v1/mediaItems'

    attr_reader :user

    def initialize(user)
      @user = user
    end

    def call
      return { success: false, error: 'Google Photos not configured' } unless configured?

      token_result = GooglePhotos::RefreshToken.new(user).call
      return { success: false, error: token_result[:error] } unless token_result[:success]

      test_api_access(token_result[:access_token])
    end

    private

    def configured?
      user.google_photos_integration_configured?
    end

    def test_api_access(access_token)
      response = HTTParty.get(
        "#{GOOGLE_PHOTOS_API_URL}?pageSize=1",
        headers: {
          'Authorization' => "Bearer #{access_token}",
          'Accept' => 'application/json'
        },
        timeout: 10
      )

      if response.success?
        { success: true, message: 'Google Photos connection verified' }
      else
        error_message = parse_error(response)
        { success: false, error: error_message }
      end
    rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
      { success: false, error: "Connection failed: #{e.message}" }
    end

    def parse_error(response)
      parsed = JSON.parse(response.body)
      parsed.dig('error', 'message') || "Request failed: #{response.code}"
    rescue JSON::ParserError
      "Request failed: #{response.code}"
    end
  end
end

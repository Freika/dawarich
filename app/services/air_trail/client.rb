# frozen_string_literal: true

module AirTrail
  class Client
    include SslConfigurable

    class Error < StandardError; end

    def initialize(url, api_key, skip_ssl_verification: false)
      @url = url.to_s.chomp('/')
      @api_key = api_key
      @skip_ssl_verification = skip_ssl_verification
    end

    def flights(scope: 'mine')
      response = HTTParty.get(
        "#{@url}/api/flight/list?scope=#{scope}",
        http_options_with_ssl_flag(@skip_ssl_verification, {
                                     headers: {
                                       'Authorization' => "Bearer #{@api_key}",
                                       'accept' => 'application/json'
                                     },
                                     timeout: 15
                                   })
      )

      raise Error, "AirTrail responded with #{response.code}" unless response.success?

      body = JSON.parse(response.body)
      raise Error, 'AirTrail returned an unsuccessful response' unless body['success']

      body['flights'] || []
    rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError => e
      raise Error, e.message
    end
  end
end

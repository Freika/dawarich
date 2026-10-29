# frozen_string_literal: true

module AirTrail
  class Client
    include SslConfigurable

    class Error < StandardError; end

    MAX_SUMMARY_PAGES = 1_000

    def initialize(url, api_key, skip_ssl_verification: false)
      @url = url.to_s.chomp('/')
      @api_key = api_key
      @skip_ssl_verification = skip_ssl_verification
    end

    def flights(scope: 'mine')
      body = get_json("/api/flight/list?scope=#{scope}")
      raise Error, 'AirTrail returned an unsuccessful response' unless body['success']

      body['flights'] || []
    end

    def track_summaries
      summaries = {}
      cursor = nil

      MAX_SUMMARY_PAGES.times do
        query = { limit: 100, cursor: cursor }.compact.to_query
        body = get_json("/api/v1/flights?#{query}")
        Array(body['data']).each { |flight| summaries[flight['id']] = flight['track'] }

        next_cursor = body.dig('page', 'nextCursor')
        break if next_cursor.blank? || next_cursor == cursor

        cursor = next_cursor
      end

      summaries
    end

    def track(flight_id)
      get_json("/api/v1/flights/#{flight_id.to_i}/track")['data']
    end

    private

    def get_json(path)
      response = HTTParty.get(
        "#{@url}#{path}",
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
      raise Error, 'AirTrail returned an unexpected response' unless body.is_a?(Hash)

      body
    rescue *Photos::ConnectionErrors::HANDLED => e
      raise Error, e.message
    end
  end
end

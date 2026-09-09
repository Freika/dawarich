# frozen_string_literal: true

module TeslaMate
  class Client
    include SslConfigurable

    class Error < StandardError; end
    class RetryableResponseError < StandardError; end

    RETRY_DELAYS = [0.05, 0.1].freeze
    DEFAULT_TIMEOUT = 30
    DEFAULT_MAX_ATTEMPTS = RETRY_DELAYS.length + 1
    RETRYABLE_ERRORS = (Photos::ConnectionErrors::RETRYABLE + [RetryableResponseError]).freeze
    HANDLED_ERRORS = (Photos::ConnectionErrors::HANDLED + [RetryableResponseError]).freeze

    def initialize(url, username: nil, password: nil, api_token: nil, skip_ssl_verification: false,
                   timeout: DEFAULT_TIMEOUT, max_attempts: DEFAULT_MAX_ATTEMPTS)
      @url = url.to_s.chomp('/')
      @username = username
      @password = password
      @api_token = api_token
      @skip_ssl_verification = skip_ssl_verification
      @timeout = timeout
      @max_attempts = max_attempts
    end

    def cars
      body = get('/api/v1/cars')
      raise Error, 'TeslaMateApi response did not contain cars data' unless body['data'].key?('cars')

      cars = body.dig('data', 'cars')
      raise Error, 'TeslaMateApi response did not contain cars data' unless cars.nil? || cars.is_a?(Array)

      cars || []
    end

    def drives(car_id, page:, show:, end_date:, start_date: nil)
      query = {
        page: positive_integer(page, 'page'),
        show: positive_integer(show, 'show'),
        endDate: end_date.iso8601
      }
      query[:startDate] = start_date.iso8601 if start_date
      body = get("/api/v1/cars/#{positive_id(car_id)}/drives", query: query)
      raise Error, 'TeslaMateApi response did not contain drives data' unless body['data'].key?('drives')

      drives = body.dig('data', 'drives')
      raise Error, 'TeslaMateApi response did not contain drives data' unless drives.nil? || drives.is_a?(Array)

      { drives: drives || [], units: body.dig('data', 'units') || {} }
    end

    def drive(car_id, drive_id)
      body = get("/api/v1/cars/#{positive_id(car_id)}/drives/#{positive_id(drive_id)}")
      drive = body.dig('data', 'drive')
      raise Error, 'TeslaMateApi response did not contain drive data' unless drive.is_a?(Hash)

      { drive: drive, units: body.dig('data', 'units') || {} }
    end

    private

    def get(path, query: nil)
      response = fetch_with_retries(path, query)
      raise Error, "TeslaMateApi responded with #{response.code}" unless response.success?

      body = JSON.parse(response.body)
      raise Error, 'TeslaMateApi returned an invalid response' unless body.is_a?(Hash)

      raise Error, body['error'].to_s if body['error'].present?
      raise Error, 'TeslaMateApi returned an invalid response' unless body['data'].is_a?(Hash)

      body
    rescue *HANDLED_ERRORS => e
      raise Error, e.message
    end

    def fetch_with_retries(path, query)
      attempts = 0

      begin
        attempts += 1
        response = HTTParty.get("#{@url}#{path}", request_options.merge(query: query).compact)
        raise RetryableResponseError, "TeslaMateApi responded with #{response.code}" if response.code.to_i >= 500

        response
      rescue *RETRYABLE_ERRORS
        raise if attempts >= @max_attempts

        sleep(RETRY_DELAYS.fetch(attempts - 1, RETRY_DELAYS.last))
        retry
      end
    end

    def positive_id(value)
      positive_integer(value, 'resource ID')
    end

    def positive_integer(value, label)
      integer = Integer(value)
      valid_numeric = !value.is_a?(Numeric) || value == integer
      raise Error, "TeslaMateApi #{label} must be a positive integer" unless valid_numeric && integer.positive?

      integer
    rescue ArgumentError, TypeError
      raise Error, "TeslaMateApi #{label} must be a positive integer"
    end

    def request_options
      options = {
        headers: { 'Accept' => 'application/json' },
        timeout: @timeout
      }

      if @username.present?
        options[:basic_auth] = { username: @username, password: @password.to_s }
      elsif @api_token.present?
        options[:headers]['Authorization'] = "Bearer #{@api_token}"
      end

      http_options_with_ssl_flag(@skip_ssl_verification, options)
    end
  end
end

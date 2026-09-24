# frozen_string_literal: true

# This integration built based on
# [September 15, 2024](https://github.com/photoprism/photoprism/releases/tag/240915-e1280b2fb)
# release of Photoprism.

class Photoprism::RequestPhotos
  include SslConfigurable
  include DayBoundable

  attr_reader :user, :photoprism_api_base_url, :photoprism_api_key, :start_date, :end_date

  def initialize(user, start_date: '1970-01-01', end_date: nil, raise_on_connection_error: false)
    @user = user
    @photoprism_api_base_url = "#{user.safe_settings.photoprism_url}/api/v1/photos"
    @photoprism_api_key = user.safe_settings.photoprism_api_key
    @start_date = start_date.presence || '1970-01-01'
    @end_date = end_date
    @raise_on_connection_error = raise_on_connection_error
  end

  def call
    if user.safe_settings.photoprism_url.blank?
      raise ArgumentError,
            I18n.t('services.photoprism.configuration.url_missing')
    end
    raise ArgumentError, I18n.t('services.photoprism.configuration.api_key_missing') if photoprism_api_key.blank?

    data = retrieve_photoprism_data

    return [] if data.blank? || data[0]['error'].present?

    time_framed_data(data, start_date, end_date)
  end

  def connection_failed?
    @connection_failed.present?
  end

  private

  def retrieve_photoprism_data
    data = []
    offset = 0

    while offset < 1_000_000
      response_data = fetch_page(offset)

      # Break on nil (fetch failed), empty array, or error response
      break if response_data.nil?
      break if response_data.blank? || (response_data.is_a?(Hash) && response_data.try(:[], 'error').present?)

      data << response_data

      offset += 1000
    end

    data.flatten
  rescue *Photos::ConnectionErrors::HANDLED => e
    Rails.logger.error("Photoprism photo fetch failed: #{e.message}")
    @connection_failed = true
    raise if @raise_on_connection_error && Photos::ConnectionErrors.retryable?(e)

    []
  end

  def fetch_page(offset)
    response = HTTParty.get(
      photoprism_api_base_url,
      http_options_with_ssl(
        @user, :photoprism, {
          headers: headers,
          query: request_params(offset),
          timeout: 10
        }
      )
    )

    result = Photoprism::ResponseValidator.validate_and_parse(response)

    unless result[:success]
      Rails.logger.error("Photoprism photo fetch failed: #{result[:error]}")
      Rails.logger.debug("Photoprism API request params: #{request_params(offset).inspect}")
      @connection_failed = true
      return nil
    end

    cache_preview_token(response.headers)

    result[:data]
  end

  def headers
    {
      'Authorization' => "Bearer #{photoprism_api_key}",
      'accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  def request_params(offset = 0)
    params = offset.zero? ? default_params : default_params.merge(offset: offset)
    params[:before] = (utc_date(end_date) + 1.day).iso8601 if end_date.present?
    params
  end

  def default_params
    {
      q: '',
      public: true,
      quality: 3,
      after: utc_date(start_date).iso8601,
      count: 1000
    }
  end

  # Photoprism filters after/before on the UTC TakenAt date, while the bounds it
  # is given arrive rendered in the application time zone.
  def utc_date(value)
    value.to_datetime.utc.to_date
  end

  # A bare date names a whole day, so an end bound written that way has to
  # reach its last instant or the final day is dropped.
  def time_framed_data(data, start_date, end_date)
    range_start = start_date.to_datetime
    range_end = (end_date || Time.current).to_datetime
    range_end = range_end.end_of_day if date_only?(end_date)

    data.flatten.select do |photo|
      taken_at = parse_taken_at(photo)
      next false if taken_at.nil?

      taken_at.between?(range_start, range_end)
    end
  end

  # TakenAtLocal is wall-clock time in the photo's own zone, serialised with a
  # trailing Z, so only TakenAt is comparable to an absolute bound.
  def parse_taken_at(photo)
    value = photo['TakenAt'].presence || photo['TakenAtLocal'].presence
    return if value.blank?

    DateTime.parse(value)
  rescue ArgumentError, TypeError
    nil
  end

  def cache_preview_token(headers)
    preview_token = headers['X-Preview-Token']

    Photoprism::CachePreviewToken.new(user, preview_token).call
  end
end

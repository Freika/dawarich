# frozen_string_literal: true

class Immich::RequestPhotos
  include SslConfigurable
  include DayBoundable

  attr_reader :user, :immich_api_base_url, :immich_api_key, :start_date, :end_date, :album_id

  def initialize(user, start_date: '1970-01-01', end_date: nil, album_id: nil, raise_on_connection_error: false)
    @user = user
    @immich_api_base_url = "#{user.safe_settings.immich_url}/api/search/metadata"
    @immich_api_key = user.safe_settings.immich_api_key
    @start_date = start_date
    @end_date = end_date
    @album_id = album_id.to_s.presence
    @raise_on_connection_error = raise_on_connection_error
  end

  def call
    raise ArgumentError, I18n.t('services.immich.configuration.api_key_missing') if immich_api_key.blank?
    raise ArgumentError, I18n.t('services.immich.configuration.url_missing') if user.safe_settings.immich_url.blank?

    data = retrieve_immich_data
    return nil if data.nil?

    time_framed_data(data)
  end

  private

  def retrieve_immich_data
    page = 1
    data = []
    max_pages = 10_000 # Prevent infinite loop

    # TODO: Handle pagination using nextPage
    while page <= max_pages
      response = HTTParty.post(
        immich_api_base_url,
        http_options_with_ssl(
          @user, :immich, {
            headers: headers,
            body: request_body(page).to_json,
            timeout: 10
          }
        )
      )

      result = Immich::ResponseValidator.validate_and_parse(response)

      unless result[:success]
        Rails.logger.error("Immich photo fetch failed: #{result[:error]}")
        return nil
      end

      Rails.logger.debug('==== IMMICH RESPONSE ====')
      Rails.logger.debug(result[:data])
      items = result[:data].dig('assets', 'items')

      break if items.blank?

      data << items

      page += 1
    end

    data.flatten
  rescue *Photos::ConnectionErrors::HANDLED => e
    Rails.logger.error("Immich photo fetch failed: #{e.message}")
    raise if @raise_on_connection_error && Photos::ConnectionErrors.retryable?(e)

    nil
  end

  def headers
    {
      'x-api-key' => immich_api_key,
      'accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  def request_body(page)
    body = {
      takenAfter: normalize_date(start_date),
      size: 1000,
      page: page,
      order: 'asc',
      withExif: true
    }
    body[:albumIds] = [album_id] if album_id.present?

    return body unless end_date

    body.merge(takenBefore: normalize_date(end_date, end_of_day: true))
  end

  def time_framed_data(data)
    start_time = parse_time(start_date)
    end_time = parse_time(end_date, end_of_day: true)
    return data unless start_time

    data.select do |photo|
      photo_time = parse_time(photo['fileCreatedAt'] || photo['localDateTime'])
      next false unless photo_time

      photo_time >= start_time && (end_time.nil? || photo_time <= end_time)
    end
  end

  def normalize_date(value, end_of_day: false)
    parsed = parse_time(value, end_of_day: end_of_day)
    parsed ? parsed.iso8601 : value
  end

  # A bare date names a whole day, so an end bound written that way has to
  # reach its last instant before the shift to UTC. Only the end bound is
  # widened; the start bound keeps the parsing it has always had.
  def parse_time(value, end_of_day: false)
    return if value.blank?

    return Time.zone.parse(value.to_s).end_of_day.utc if end_of_day && date_only?(value)

    Time.parse(value.to_s).utc
  rescue ArgumentError, TypeError
    nil
  end
end

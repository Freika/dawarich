# frozen_string_literal: true

class Immich::RequestPhotos
  include SslConfigurable

  attr_reader :user, :immich_api_base_url, :immich_api_key, :start_date, :end_date

  def initialize(user, start_date: '1970-01-01', end_date: nil)
    @user = user
    @immich_api_base_url = URI.parse("#{user.safe_settings.immich_url}/api/search/metadata")
    @immich_api_key = user.safe_settings.immich_api_key
    @start_date = start_date
    @end_date = end_date
  end

  def call
    raise ArgumentError, 'Immich API key is missing' if immich_api_key.blank?
    raise ArgumentError, 'Immich URL is missing'     if user.safe_settings.immich_url.blank?

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
        http_options_with_ssl(@user, :immich, {
                                headers: headers,
                                body: request_body(page),
                                timeout: 10
                              })
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
  rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.error("Immich photo fetch failed: #{e.message}")
    nil
  end

  def headers
    {
      'x-api-key' => immich_api_key,
      'accept' => 'application/json'
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

    return body unless end_date

    body.merge(takenBefore: normalize_date(end_date))
  end

  def time_framed_data(data)
    start_time = parse_time(start_date)
    end_time = parse_time(end_date)
    return data unless start_time

    data.select do |photo|
      photo_time = parse_time(photo['localDateTime'])
      next false unless photo_time

      photo_time >= start_time && (end_time.nil? || photo_time <= end_time)
    end
  end

  def normalize_date(value)
    parsed = parse_time(value)
    parsed ? parsed.iso8601 : value
  end

  def parse_time(value)
    return if value.blank?

    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end

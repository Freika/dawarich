# frozen_string_literal: true

class Immich::RequestPhotos
  attr_reader :user, :immich_api_base_url, :immich_api_key, :start_date, :end_date

  def initialize(user, start_date: '1970-01-01', end_date: nil)
    @user = user
    @immich_api_base_url = URI.parse("#{user.safe_settings.immich_url}/api/search/metadata")
    @immich_api_key = user.safe_settings.immich_api_key
    @start_date = normalize_date(start_date)
    @end_date = normalize_date(end_date)
  end

  def call
    raise ArgumentError, 'Immich API key is missing' if immich_api_key.blank?
    raise ArgumentError, 'Immich URL is missing'     if user.safe_settings.immich_url.blank?

    data = retrieve_immich_data

    time_framed_data(data)
  end

  private

  def normalize_date(raw_date)
    return nil if raw_date.nil?

    time = Time.zone.parse(raw_date.to_s)
    time.utc.iso8601
  rescue ArgumentError => e
    raise ArgumentError, "Invalid date format for '#{raw_date}': #{e.message}"
  end

  def retrieve_immich_data
    page = 1
    data = []
    max_pages = 10_000 # Prevent infinite loop

    # TODO: Handle pagination using nextPage
    while page <= max_pages
      response = JSON.parse(
        HTTParty.post(
          immich_api_base_url, headers: headers, body: request_body(page)
        ).body
      )
      Rails.logger.debug('==== IMMICH RESPONSE ====')
      Rails.logger.debug(response)
      items = response.dig('assets', 'items')

      break if items.blank?

      data << items

      page += 1
    end

    data.flatten
  end

  def headers
    {
      'x-api-key' => immich_api_key,
      'accept' => 'application/json'
    }
  end

  def request_body(page)
    body = {
      takenAfter: start_date,
      size: 1000,
      page: page,
      order: 'asc',
      withExif: true
    }

    return body unless end_date

    body.merge(takenBefore: end_date)
  end

  def time_framed_data(data)
    data.select do |photo|
      photo['localDateTime'] >= start_date &&
        (end_date.nil? || photo['localDateTime'] <= end_date)
    end
  end
end

# frozen_string_literal: true

class Immich::RequestPhotos
  attr_reader :user, :immich_api_base_url, :immich_api_key, :start_date, :end_date

  def initialize(user, start_date: '1970-01-01', end_date: nil)
    @user = user
    @immich_api_base_url = "#{user.settings['immich_url']}/api/search/metadata"
    @immich_api_key = user.settings['immich_api_key']
    @start_date = start_date
    @end_date = end_date
  end

  def call
    raise ArgumentError, 'Immich API key is missing' if immich_api_key.blank?
    raise ArgumentError, 'Immich URL is missing'     if user.settings['immich_url'].blank?

    data = retrieve_immich_data

    time_framed_data(data)
  end

  private

  def retrieve_immich_data
    page = 1
    data = []
    max_pages = 10_000 # Prevent infinite loop

    while page <= max_pages
      response = JSON.parse(
        HTTParty.post(
          immich_api_base_url, headers: headers, body: request_body(page)
        ).body
      )

      items = response.dig('assets', 'items')

      if items.blank?
        Rails.logger.debug('==== IMMICH RESPONSE WITH NO ITEMS ====')
        Rails.logger.debug(response)
        Rails.logger.debug('==== IMMICH RESPONSE WITH NO ITEMS ====')

        break
      end

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

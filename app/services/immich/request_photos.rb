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
    retrieve_immich_data
  end

  private

  def retrieve_immich_data
    page = 1
    data = []
    max_pages = 100_000 # Prevent infinite loop

    while page <= max_pages
      body = request_body(page)
      response = JSON.parse(HTTParty.post(immich_api_base_url, headers: headers, body: body).body)

      items = response.dig('assets', 'items')

      break if items.empty?

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
      createdAfter: start_date,
      size: 1000,
      page: page,
      order: 'asc',
      withExif: true
    }

    return body unless end_date

    body.merge(createdBefore: end_date)
  end
end

# frozen_string_literal: true

class Photoprism::RequestPhotos
  class Error < StandardError; end
  attr_reader :user, :photoprism_api_base_url, :photoprism_api_key, :start_date, :end_date

  def initialize(user, start_date: '1970-01-01', end_date: nil)
    @user = user
    @photoprism_api_base_url = "#{user.settings['photoprism_url']}/api/v1/photos"
    @photoprism_api_key = user.settings['photoprism_api_key']
    @start_date = start_date
    @end_date = end_date
  end

  def call
    raise ArgumentError, 'Photoprism URL is missing' if user.settings['photoprism_url'].blank?
    raise ArgumentError, 'Photoprism API key is missing' if photoprism_api_key.blank?

    data = retrieve_photoprism_data

    time_framed_data(data)
  end

  private

  def retrieve_photoprism_data
    data = []
    offset = 0

    while offset < 1_000_000
      response_data = fetch_page(offset)
      break unless response_data

      data << response_data
      break if response_data.empty?

      offset += 1000
    end

    data
  end

  def fetch_page(offset)
    response = HTTParty.get(
      photoprism_api_base_url,
      headers: headers,
      query: request_params(offset)
    )

    raise Error, "Photoprism API returned #{response.code}: #{response.body}" if response.code != 200

    JSON.parse(response.body)
  end

  def headers
    {
      'Authorization' => "Bearer #{photoprism_api_key}",
      'accept' => 'application/json'
    }
  end

  def request_params(offset = 0)
    params = offset.zero? ? default_params : default_params.merge(offset: offset)
    params[:before] = end_date if end_date.present?
    params
  end

  def default_params
    {
      q: '',
      public: true,
      quality: 3,
      after: start_date,
      count: 1000
    }
  end

  def time_framed_data(data)
    data.flatten.select do |photo|
      taken_at = DateTime.parse(photo['TakenAtLocal'])
      end_date ||= Time.current
      taken_at.between?(start_date.to_datetime, end_date.to_datetime)
    end
  end
end

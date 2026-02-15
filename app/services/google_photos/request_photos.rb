# frozen_string_literal: true

module GooglePhotos
  class RequestPhotos
    GOOGLE_PHOTOS_SEARCH_URL = 'https://photoslibrary.googleapis.com/v1/mediaItems:search'
    PAGE_SIZE = 100

    attr_reader :user, :start_date, :end_date

    def initialize(user, start_date: '1970-01-01', end_date: nil)
      @user = user
      @start_date = start_date
      @end_date = end_date
    end

    def call
      token_result = GooglePhotos::RefreshToken.new(user).call
      return nil unless token_result[:success]

      @access_token = token_result[:access_token]
      data = retrieve_photos
      return nil if data.nil?

      data
    end

    private

    def retrieve_photos
      photos = []
      page_token = nil
      max_pages = 100 # Safety limit

      max_pages.times do
        response = fetch_page(page_token)
        result = GooglePhotos::ResponseValidator.validate_and_parse(response)

        unless result[:success]
          Rails.logger.error("Google Photos fetch failed: #{result[:error]}")
          return nil
        end

        items = result[:data]['mediaItems'] || []
        photos.concat(filter_photos(items))

        page_token = result[:data]['nextPageToken']
        break if page_token.blank?
      end

      photos
    rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.error("Google Photos fetch failed: #{e.message}")
      nil
    end

    def fetch_page(page_token)
      HTTParty.post(
        GOOGLE_PHOTOS_SEARCH_URL,
        headers: headers,
        body: request_body(page_token).to_json,
        timeout: 30
      )
    end

    def headers
      {
        'Authorization' => "Bearer #{@access_token}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
    end

    def request_body(page_token)
      body = {
        pageSize: PAGE_SIZE,
        filters: {
          mediaTypeFilter: {
            mediaTypes: ['PHOTO']
          },
          dateFilter: date_filter
        }
      }

      body[:pageToken] = page_token if page_token.present?
      body
    end

    def date_filter
      filter = {}

      if start_date.present? && end_date.present?
        filter[:ranges] = [{
          startDate: parse_date(start_date),
          endDate: parse_date(end_date)
        }]
      elsif start_date.present?
        # Only start date - filter from start to today
        filter[:ranges] = [{
          startDate: parse_date(start_date),
          endDate: parse_date(Time.current.to_date.to_s)
        }]
      end

      filter
    end

    def parse_date(date_string)
      date = Date.parse(date_string.to_s)
      { year: date.year, month: date.month, day: date.day }
    rescue ArgumentError
      nil
    end

    def filter_photos(items)
      items.select do |item|
        # Only include items with location data
        item.dig('mediaMetadata', 'photo').present?
      end
    end
  end
end

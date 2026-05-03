# frozen_string_literal: true

class ReverseGeocoding::Points::FetchData
  attr_reader :point

  def initialize(point_id, force: false)
    @force = force
    @point = Point.find(point_id)
  rescue ActiveRecord::RecordNotFound => e
    ExceptionReporter.call(e)

    Rails.logger.error("Point with id #{point_id} not found: #{e.message}")
  end

  def call
    return if point.blank?
    return if point.reverse_geocoded? && !@force
    return unless point.timestamp.present? && point.lonlat.present?

    update_point_with_geocoding_data
  end

  private

  DEADLOCK_MAX_RETRIES = 3

  def update_point_with_geocoding_data
    response = Geocoder.search([point.lat, point.lon]).first
    return if response.blank? || response.data['error'].present?

    country_record = Country.find_by(name: response.country) if response.country

    with_deadlock_retry do
      point.update!(
        city: response.city,
        country_name: response.country,
        country_id: country_record&.id,
        geodata: DawarichSettings.store_geodata? ? response.data : {},
        reverse_geocoded_at: Time.current
      )
    end
  rescue StandardError => e
    Rails.logger.error("Reverse geocoding error for point #{point.id}: #{e.message}")
    ExceptionReporter.call(e)
  end

  def with_deadlock_retry
    retries = 0
    begin
      yield
    rescue ActiveRecord::Deadlocked => e
      retries += 1
      raise e if retries > DEADLOCK_MAX_RETRIES

      sleep(0.1 * retries)
      retry
    end
  end
end

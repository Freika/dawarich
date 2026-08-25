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

  WRITE_MAX_RETRIES = 3
  WRITE_CONTENTION_ERRORS = [
    ActiveRecord::Deadlocked,
    ActiveRecord::LockWaitTimeout,
    ActiveRecord::QueryCanceled
  ].freeze

  def update_point_with_geocoding_data
    response = Geocoding::Search.call(user: point.user_id, query: [point.lat, point.lon]).first

    if response.blank?
      with_write_retry { point.update!(reverse_geocoded_at: Time.current) }
      return
    end

    return if response.data['error'].present?

    country_record = find_country(response) if response.country

    with_write_retry do
      point.update!(
        city: response.city,
        country_name: response.country,
        country_id: country_record&.id,
        geodata: DawarichSettings.store_geodata? ? response.data : {},
        reverse_geocoded_at: Time.current
      )
    end
  rescue *ReverseGeocoding::ProviderErrors::TRANSIENT => e
    Rails.logger.warn("Reverse geocoding provider error for point #{point.id}: #{e.message}")
  rescue OpenSSL::SSL::SSLError => e
    if ReverseGeocoding::ProviderErrors.transient_tls?(e)
      Rails.logger.warn("Reverse geocoding provider error for point #{point.id}: #{e.message}")
    else
      Rails.logger.error("Reverse geocoding error for point #{point.id}: #{e.message}")
      ExceptionReporter.call(e)
    end
  rescue StandardError => e
    Rails.logger.error("Reverse geocoding error for point #{point.id}: #{e.message}")
    ExceptionReporter.call(e)
  end

  # ISO code first: it is naming-scheme-proof, where the name match needs the
  # alias map to bridge geocoder names and the seeded Natural Earth ones.
  # Geocoder's Result::Base#country_code raises for lookups that don't carry
  # a code, hence the rescue.
  def find_country(response)
    code = begin
      response.country_code if response.respond_to?(:country_code)
    rescue StandardError
      nil
    end

    country = Country.find_by(iso_a2: code.upcase) if code.present?
    country || Country.matching_name(response.country)
  end

  def with_write_retry
    retries = 0
    begin
      yield
    rescue *WRITE_CONTENTION_ERRORS => e
      retries += 1
      raise e if retries > WRITE_MAX_RETRIES

      sleep((0.1 * retries) + (rand * 0.05))
      retry
    end
  end
end

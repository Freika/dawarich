# frozen_string_literal: true

class Trips::Countries
  FILE_PATH = Rails.root.join('lib/assets/countries.json')

  def initialize(trip, batch_count = 2)
    @trip = trip
    @batch_count = batch_count
    @factory = RGeo::Geographic.spherical_factory
    @file = File.read(FILE_PATH)
    @countries_features =
      RGeo::GeoJSON.decode(@file, json_parser: :json, geo_factory: @factory)
  end

  def call
    all_points = @trip.points.to_a
    total_points = all_points.size

    # Return empty hash if no points
    return {} if total_points.zero?

    batches = split_into_batches(all_points, @batch_count)
    threads_results = process_batches_in_threads(batches, total_points)

    merge_thread_results(threads_results).uniq.compact
  end

  private

  def split_into_batches(points, batch_count)
    batch_count = [batch_count, 1].max # Ensure batch_count is at least 1
    batch_size = (points.size / batch_count.to_f).ceil
    points.each_slice(batch_size).to_a
  end

  def process_batches_in_threads(batches, total_points)
    threads_results = []
    threads = []

    batches.each do |batch|
      threads << Thread.new do
        threads_results << process_batch(batch)
      end
    end

    threads.each(&:join)
    threads_results
  end

  def merge_thread_results(threads_results)
    countries = []

    threads_results.each do |result|
      countries.concat(result)
    end

    countries
  end

  def process_batch(points)
    points.map do |point|
      country_code = geocode_point(point)
      next unless country_code

      country_code
    end
  end

  def geocode_point(point)
    lonlat = point.lonlat
    return nil unless lonlat

    latitude = lonlat.y
    longitude = lonlat.x

    fetch_country_code(latitude, longitude)
  end

  def fetch_country_code(latitude, longitude)
    results = Geocoder.search([latitude, longitude], limit: 1)
    return nil unless results.any?

    result = results.first
    result.data['properties']['countrycode']
  rescue StandardError => e
    Rails.logger.error("Error geocoding point: #{e.message}")

    ExceptionReporter.call(e)

    nil
  end
end

# frozen_string_literal: true

require 'rgeo/geo_json'
require 'rgeo'
require 'json'
require 'geocoder'

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
    country_counts = merge_thread_results(threads_results)

    log_results(country_counts, total_points)
    country_counts.sort_by { |_country, count| -count }.to_h
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

    batches.each_with_index do |batch, batch_index|
      start_index = batch_index * batch.size + 1
      threads << Thread.new do
        threads_results << process_batch(batch, start_index, total_points)
      end
    end

    threads.each(&:join)
    threads_results
  end

  def merge_thread_results(threads_results)
    country_counts = {}

    threads_results.each do |result|
      result.each do |country, count|
        country_counts[country] ||= 0
        country_counts[country] += count
      end
    end

    country_counts
  end

  def log_results(country_counts, total_points)
    total_counted = country_counts.values.sum
    Rails.logger.info("Processed #{total_points} points and found #{country_counts.size} countries")
    Rails.logger.info("Points counted: #{total_counted} out of #{total_points}")
  end

  def process_batch(points, start_index, total_points)
    country_counts = {}

    points.each_with_index do |point, idx|
      current_index = start_index + idx
      country_code = geocode_point(point, current_index, total_points)
      next unless country_code

      country_counts[country_code] ||= 0
      country_counts[country_code] += 1
    end

    country_counts
  end

  def geocode_point(point, current_index, total_points)
    lonlat = point.lonlat
    return nil unless lonlat

    latitude = lonlat.y
    longitude = lonlat.x

    log_processing_point(current_index, total_points, latitude, longitude)
    country_code = fetch_country_code(latitude, longitude)
    log_found_country(country_code, latitude, longitude) if country_code

    country_code
  end

  def log_processing_point(current_index, total_points, latitude, longitude)
    thread_id = Thread.current.object_id
    Rails.logger.info(
      "Thread #{thread_id}: Processing point #{current_index} of #{total_points}: lat=#{latitude}, lon=#{longitude}"
    )
  end

  def log_found_country(country_code, latitude, longitude)
    thread_id = Thread.current.object_id
    Rails.logger.info("Thread #{thread_id}: Found country: #{country_code} for point at #{latitude}, #{longitude}")
  end

  def fetch_country_code(latitude, longitude)
    results = Geocoder.search([latitude, longitude], limit: 1)
    return nil unless results.any?

    result = results.first
    result.data['properties']['countrycode']
  rescue StandardError => e
    Rails.logger.error("Error geocoding point: #{e.message}")
    nil
  end
end

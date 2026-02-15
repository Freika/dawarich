# frozen_string_literal: true

class Users::ImportData::Trips
  BATCH_SIZE = 1000

  def initialize(user, trips_data)
    @user = user
    @trips_data = trips_data
  end

  def call
    return 0 unless trips_data.is_a?(Array)

    Rails.logger.info "Importing #{trips_data.size} trips for user: #{user.email}"

    valid_trips = filter_and_prepare_trips

    if valid_trips.empty?
      Rails.logger.info 'Trips import completed. Created: 0'
      return 0
    end

    deduplicated_trips = filter_existing_trips(valid_trips)

    if deduplicated_trips.size < valid_trips.size
      Rails.logger.debug "Skipped #{valid_trips.size - deduplicated_trips.size} duplicate trips"
    end

    total_created = bulk_import_trips(deduplicated_trips)

    Rails.logger.info "Trips import completed. Created: #{total_created}"
    total_created
  end

  private

  attr_reader :user, :trips_data

  def filter_and_prepare_trips
    valid_trips = []
    skipped_count = 0

    trips_data.each do |trip_data|
      next unless trip_data.is_a?(Hash)

      unless valid_trip_data?(trip_data)
        skipped_count += 1
        next
      end

      prepared_attributes = prepare_trip_attributes(trip_data)
      valid_trips << prepared_attributes if prepared_attributes
    end

    Rails.logger.warn "Skipped #{skipped_count} trips with invalid or missing required data" if skipped_count.positive?

    valid_trips
  end

  def prepare_trip_attributes(trip_data)
    attributes = trip_data.except('created_at', 'updated_at')

    attributes['user_id'] = user.id
    attributes['created_at'] = Time.current
    attributes['updated_at'] = Time.current

    attributes.symbolize_keys
  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to prepare trip attributes')

    nil
  end

  def filter_existing_trips(trips)
    return trips if trips.empty?

    existing_trips_lookup = {}
    user.trips.select(:name, :started_at, :ended_at).each do |trip|
      key = [trip.name, normalize_timestamp(trip.started_at), normalize_timestamp(trip.ended_at)]
      existing_trips_lookup[key] = true
    end

    trips.reject do |trip|
      key = [trip[:name], normalize_timestamp(trip[:started_at]), normalize_timestamp(trip[:ended_at])]
      if existing_trips_lookup[key]
        Rails.logger.debug "Trip already exists: #{trip[:name]}"
        true
      else
        false
      end
    end
  end

  def normalize_timestamp(timestamp)
    case timestamp
    when String
      Time.parse(timestamp).utc.iso8601
    when Time, DateTime
      timestamp.utc.iso8601
    else
      timestamp.to_s
    end
  rescue StandardError
    timestamp.to_s
  end

  def bulk_import_trips(trips)
    total_created = 0

    trips.each_slice(BATCH_SIZE) do |batch|
      # rubocop:disable Rails/SkipsModelValidations
      result = Trip.upsert_all(
        batch,
        returning: %w[id],
        on_duplicate: :skip
      )
      # rubocop:enable Rails/SkipsModelValidations

      batch_created = result.count
      total_created += batch_created

      Rails.logger.debug(
        "Processed batch of #{batch.size} trips, created #{batch_created}, total created: #{total_created}"
      )
    rescue StandardError => e
      ExceptionReporter.call(e, 'Failed to process trip batch')
    end

    total_created
  end

  def valid_trip_data?(trip_data)
    return false unless trip_data.is_a?(Hash)

    return false unless validate_trip_name(trip_data)
    return false unless validate_trip_started_at(trip_data)
    return false unless validate_trip_ended_at(trip_data)

    true
  rescue StandardError => e
    Rails.logger.debug "Trip validation failed: #{e.message} for data: #{trip_data.inspect}"
    false
  end

  def validate_trip_name(trip_data)
    if trip_data['name'].present?
      true
    else
      Rails.logger.debug 'Trip validation failed: Name can\'t be blank'
      false
    end
  end

  def validate_trip_started_at(trip_data)
    if trip_data['started_at'].present?
      true
    else
      Rails.logger.debug 'Trip validation failed: Started at can\'t be blank'
      false
    end
  end

  def validate_trip_ended_at(trip_data)
    if trip_data['ended_at'].present?
      true
    else
      Rails.logger.debug 'Trip validation failed: Ended at can\'t be blank'
      false
    end
  end
end

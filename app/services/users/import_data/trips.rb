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

    # Filter valid trips and prepare for bulk import
    valid_trips = filter_and_prepare_trips

    if valid_trips.empty?
      Rails.logger.info "Trips import completed. Created: 0"
      return 0
    end

    # Remove existing trips to avoid duplicates
    deduplicated_trips = filter_existing_trips(valid_trips)

    if deduplicated_trips.size < valid_trips.size
      Rails.logger.debug "Skipped #{valid_trips.size - deduplicated_trips.size} duplicate trips"
    end

    # Bulk import in batches
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

      # Skip trips with missing required data
      unless valid_trip_data?(trip_data)
        skipped_count += 1
        next
      end

      # Prepare trip attributes for bulk insert
      prepared_attributes = prepare_trip_attributes(trip_data)
      valid_trips << prepared_attributes if prepared_attributes
    end

    if skipped_count > 0
      Rails.logger.warn "Skipped #{skipped_count} trips with invalid or missing required data"
    end

    valid_trips
  end

  def prepare_trip_attributes(trip_data)
    # Start with base attributes, excluding timestamp fields
    attributes = trip_data.except('created_at', 'updated_at')

    # Add required attributes for bulk insert
    attributes['user_id'] = user.id
    attributes['created_at'] = Time.current
    attributes['updated_at'] = Time.current

    # Convert string keys to symbols for consistency
    attributes.symbolize_keys
  rescue StandardError => e
    Rails.logger.error "Failed to prepare trip attributes: #{e.message}"
    Rails.logger.error "Trip data: #{trip_data.inspect}"
    nil
  end

  def filter_existing_trips(trips)
    return trips if trips.empty?

    # Build lookup hash of existing trips for this user
    existing_trips_lookup = {}
    user.trips.select(:name, :started_at, :ended_at).each do |trip|
      # Normalize timestamp values for consistent comparison
      key = [trip.name, normalize_timestamp(trip.started_at), normalize_timestamp(trip.ended_at)]
      existing_trips_lookup[key] = true
    end

    # Filter out trips that already exist
    filtered_trips = trips.reject do |trip|
      # Normalize timestamp values for consistent comparison
      key = [trip[:name], normalize_timestamp(trip[:started_at]), normalize_timestamp(trip[:ended_at])]
      if existing_trips_lookup[key]
        Rails.logger.debug "Trip already exists: #{trip[:name]}"
        true
      else
        false
      end
    end

    filtered_trips
  end

  def normalize_timestamp(timestamp)
    case timestamp
    when String
      # Parse string and convert to iso8601 format for consistent comparison
      Time.parse(timestamp).utc.iso8601
    when Time, DateTime
      # Convert time objects to iso8601 format for consistent comparison
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
      begin
        # Use upsert_all to efficiently bulk insert trips
        result = Trip.upsert_all(
          batch,
          returning: %w[id],
          on_duplicate: :skip
        )

        batch_created = result.count
        total_created += batch_created

        Rails.logger.debug "Processed batch of #{batch.size} trips, created #{batch_created}, total created: #{total_created}"

      rescue StandardError => e
        Rails.logger.error "Failed to process trip batch: #{e.message}"
        Rails.logger.error "Batch size: #{batch.size}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(3).join('\n')}"
        # Continue with next batch instead of failing completely
      end
    end

    total_created
  end

  def valid_trip_data?(trip_data)
    # Check for required fields
    return false unless trip_data.is_a?(Hash)

    unless trip_data['name'].present?
      Rails.logger.error "Failed to create trip: Validation failed: Name can't be blank"
      return false
    end

    unless trip_data['started_at'].present?
      Rails.logger.error "Failed to create trip: Validation failed: Started at can't be blank"
      return false
    end

    unless trip_data['ended_at'].present?
      Rails.logger.error "Failed to create trip: Validation failed: Ended at can't be blank"
      return false
    end

    true
  rescue StandardError => e
    Rails.logger.debug "Trip validation failed: #{e.message} for data: #{trip_data.inspect}"
    false
  end
end

# frozen_string_literal: true

class Users::ImportData::Points
  BATCH_SIZE = 1000

  def initialize(user, points_data)
    @user = user
    @points_data = points_data
  end

  def call
    return 0 unless points_data.is_a?(Array)

    puts "=== POINTS SERVICE DEBUG ==="
    puts "Points data is array: #{points_data.is_a?(Array)}"
    puts "Points data size: #{points_data.size}"

    Rails.logger.info "Importing #{points_data.size} points for user: #{user.email}"
    Rails.logger.debug "First point sample: #{points_data.first.inspect}"

    # Pre-load reference data for efficient bulk processing
    preload_reference_data

    # Filter valid points and prepare for bulk import
    valid_points = filter_and_prepare_points

    puts "Valid points after filtering: #{valid_points.size}"

    if valid_points.empty?
      puts "No valid points after filtering - returning 0"
      Rails.logger.warn "No valid points to import after filtering"
      Rails.logger.debug "Original points_data size: #{points_data.size}"
      return 0
    end

    # Remove duplicates based on unique constraint
    deduplicated_points = deduplicate_points(valid_points)

    puts "Deduplicated points: #{deduplicated_points.size}"

    Rails.logger.info "Prepared #{deduplicated_points.size} unique valid points (#{points_data.size - deduplicated_points.size} duplicates/invalid skipped)"

    # Bulk import in batches
    total_created = bulk_import_points(deduplicated_points)

    puts "Total created by bulk import: #{total_created}"

    Rails.logger.info "Points import completed. Created: #{total_created}"
    total_created
  end

  private

  attr_reader :user, :points_data, :imports_lookup, :countries_lookup, :visits_lookup

  def preload_reference_data
    # Pre-load imports for this user with multiple lookup keys for flexibility
    @imports_lookup = {}
    user.imports.each do |import|
      # Create keys for both string and integer source representations
      string_key = [import.name, import.source, import.created_at.utc.iso8601]
      integer_key = [import.name, Import.sources[import.source], import.created_at.utc.iso8601]

      @imports_lookup[string_key] = import
      @imports_lookup[integer_key] = import
    end
    Rails.logger.debug "Loaded #{user.imports.size} imports with #{@imports_lookup.size} lookup keys"

    # Pre-load all countries for efficient lookup
    @countries_lookup = {}
    Country.all.each do |country|
      # Index by all possible lookup keys
      @countries_lookup[[country.name, country.iso_a2, country.iso_a3]] = country
      @countries_lookup[country.name] = country
    end
    Rails.logger.debug "Loaded #{Country.count} countries for lookup"

    # Pre-load visits for this user
    @visits_lookup = user.visits.index_by { |visit|
      [visit.name, visit.started_at.utc.iso8601, visit.ended_at.utc.iso8601]
    }
    Rails.logger.debug "Loaded #{@visits_lookup.size} visits for lookup"
  end

  def filter_and_prepare_points
    valid_points = []
    skipped_count = 0

    points_data.each_with_index do |point_data, index|
      next unless point_data.is_a?(Hash)

      # Skip points with invalid or missing required data
      unless valid_point_data?(point_data)
        skipped_count += 1
        Rails.logger.debug "Skipped point #{index}: invalid data - #{point_data.slice('timestamp', 'longitude', 'latitude', 'lonlat')}"
        next
      end

      # Prepare point attributes for bulk insert
      prepared_attributes = prepare_point_attributes(point_data)
      unless prepared_attributes
        skipped_count += 1
        Rails.logger.debug "Skipped point #{index}: failed to prepare attributes"
        next
      end

      valid_points << prepared_attributes
    end

    if skipped_count > 0
      Rails.logger.warn "Skipped #{skipped_count} points with invalid or missing required data"
    end

    Rails.logger.debug "Filtered #{valid_points.size} valid points from #{points_data.size} total"
    valid_points
  end

  def prepare_point_attributes(point_data)
    # Start with base attributes, excluding fields that need special handling
    attributes = point_data.except(
      'created_at',
      'updated_at',
      'import_reference',
      'country_info',
      'visit_reference',
      'country'  # Exclude the string country field - handled via country_info relationship
    )

    # Handle lonlat reconstruction if missing (for backward compatibility)
    ensure_lonlat_field(attributes, point_data)

    # Remove longitude/latitude after lonlat reconstruction to ensure consistent keys
    attributes.delete('longitude')
    attributes.delete('latitude')

    # Add required attributes for bulk insert
    attributes['user_id'] = user.id
    attributes['created_at'] = Time.current
    attributes['updated_at'] = Time.current

    # Resolve foreign key relationships
    resolve_import_reference(attributes, point_data['import_reference'])
    resolve_country_reference(attributes, point_data['country_info'])
    resolve_visit_reference(attributes, point_data['visit_reference'])

    # Convert string keys to symbols for consistency with Point model
    result = attributes.symbolize_keys

    Rails.logger.debug "Prepared point attributes: #{result.slice(:lonlat, :timestamp, :import_id, :country_id, :visit_id)}"
    result
  rescue StandardError => e
    Rails.logger.error "Failed to prepare point attributes: #{e.message}"
    Rails.logger.error "Point data: #{point_data.inspect}"
    nil
  end

    def resolve_import_reference(attributes, import_reference)
    return unless import_reference.is_a?(Hash)

    # Normalize timestamp format to ISO8601 for consistent lookup
    created_at = normalize_timestamp_for_lookup(import_reference['created_at'])

    import_key = [
      import_reference['name'],
      import_reference['source'],
      created_at
    ]

    import = imports_lookup[import_key]
    if import
      attributes['import_id'] = import.id
      Rails.logger.debug "Resolved import reference: #{import_reference['name']} -> #{import.id}"
    else
      Rails.logger.debug "Import not found for reference: #{import_reference.inspect}"
      Rails.logger.debug "Available imports: #{imports_lookup.keys.inspect}"
    end
  end

  def resolve_country_reference(attributes, country_info)
    return unless country_info.is_a?(Hash)

    # Try to find country by all attributes first
    country_key = [country_info['name'], country_info['iso_a2'], country_info['iso_a3']]
    country = countries_lookup[country_key]

    # If not found by all attributes, try to find by name only
    if country.nil? && country_info['name'].present?
      country = countries_lookup[country_info['name']]
    end

    if country
      attributes['country_id'] = country.id
      Rails.logger.debug "Resolved country reference: #{country_info['name']} -> #{country.id}"
    else
      Rails.logger.debug "Country not found for: #{country_info.inspect}"
    end
  end



  def resolve_visit_reference(attributes, visit_reference)
    return unless visit_reference.is_a?(Hash)

    # Normalize timestamp formats to ISO8601 for consistent lookup
    started_at = normalize_timestamp_for_lookup(visit_reference['started_at'])
    ended_at = normalize_timestamp_for_lookup(visit_reference['ended_at'])

    visit_key = [
      visit_reference['name'],
      started_at,
      ended_at
    ]

    visit = visits_lookup[visit_key]
    if visit
      attributes['visit_id'] = visit.id
      Rails.logger.debug "Resolved visit reference: #{visit_reference['name']} -> #{visit.id}"
    else
      Rails.logger.debug "Visit not found for reference: #{visit_reference.inspect}"
      Rails.logger.debug "Available visits: #{visits_lookup.keys.inspect}"
    end
  end

  def deduplicate_points(points)
    points.uniq { |point| [point[:lonlat], point[:timestamp], point[:user_id]] }
  end

  # Ensure all points have the same keys for upsert_all compatibility
  def normalize_point_keys(points)
    # Get all possible keys from all points
    all_keys = points.flat_map(&:keys).uniq

    # Normalize each point to have all keys (with nil for missing ones)
    points.map do |point|
      normalized = {}
      all_keys.each do |key|
        normalized[key] = point[key]
      end
      normalized
    end
  end

  def bulk_import_points(points)
    total_created = 0

    puts "=== BULK IMPORT DEBUG ==="
    puts "About to bulk import #{points.size} points"
    puts "First point for import: #{points.first.inspect}"

    points.each_slice(BATCH_SIZE) do |batch|
      begin
        Rails.logger.debug "Processing batch of #{batch.size} points"
        Rails.logger.debug "First point in batch: #{batch.first.inspect}"

        puts "Processing batch of #{batch.size} points"
        puts "Sample point attributes: #{batch.first.slice(:lonlat, :timestamp, :user_id, :import_id, :country_id, :visit_id)}"

        # Normalize all points to have the same keys for upsert_all compatibility
        normalized_batch = normalize_point_keys(batch)

        # Use upsert_all to efficiently bulk insert/update points
        result = Point.upsert_all(
          normalized_batch,
          unique_by: %i[lonlat timestamp user_id],
          returning: %w[id],
          on_duplicate: :skip
        )

        batch_created = result.count
        total_created += batch_created

        puts "Batch result count: #{batch_created}"

        Rails.logger.debug "Processed batch of #{batch.size} points, created #{batch_created}, total created: #{total_created}"

      rescue StandardError => e
        puts "Batch import failed: #{e.message}"
        puts "Backtrace: #{e.backtrace.first(3).join('\n')}"
        Rails.logger.error "Failed to process point batch: #{e.message}"
        Rails.logger.error "Batch size: #{batch.size}"
        Rails.logger.error "First point in failed batch: #{batch.first.inspect}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
        # Continue with next batch instead of failing completely
      end
    end

    puts "Total created across all batches: #{total_created}"

        total_created
  end

  def valid_point_data?(point_data)
    # Check for required fields
    return false unless point_data.is_a?(Hash)
    return false unless point_data['timestamp'].present?

    # Check if we have either lonlat or longitude/latitude
    has_lonlat = point_data['lonlat'].present? && point_data['lonlat'].is_a?(String) && point_data['lonlat'].start_with?('POINT(')
    has_coordinates = point_data['longitude'].present? && point_data['latitude'].present?

    return false unless has_lonlat || has_coordinates

    true
  rescue StandardError => e
    Rails.logger.debug "Point validation failed: #{e.message} for data: #{point_data.inspect}"
    false
  end

  def ensure_lonlat_field(attributes, point_data)
    # If lonlat is missing but we have longitude/latitude, reconstruct it
    if attributes['lonlat'].blank? && point_data['longitude'].present? && point_data['latitude'].present?
      longitude = point_data['longitude'].to_f
      latitude = point_data['latitude'].to_f
      attributes['lonlat'] = "POINT(#{longitude} #{latitude})"
      Rails.logger.debug "Reconstructed lonlat: #{attributes['lonlat']}"
    end
  end

  def normalize_timestamp_for_lookup(timestamp)
    return nil if timestamp.blank?

    case timestamp
    when String
      # Parse string timestamp and convert to UTC ISO8601 format
      Time.parse(timestamp).utc.iso8601
    when Time, DateTime
      # Convert time objects to UTC ISO8601 format
      timestamp.utc.iso8601
    else
      # Fallback to string representation
      timestamp.to_s
    end
  rescue StandardError => e
    Rails.logger.debug "Failed to normalize timestamp #{timestamp}: #{e.message}"
    timestamp.to_s
  end
end

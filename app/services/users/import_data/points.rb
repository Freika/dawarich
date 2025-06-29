# frozen_string_literal: true

class Users::ImportData::Points
  BATCH_SIZE = 1000

  def initialize(user, points_data)
    @user = user
    @points_data = points_data
  end

  def call
    return 0 unless points_data.is_a?(Array)

    Rails.logger.info "Importing #{points_data.size} points for user: #{user.email}"

    # Pre-load reference data for efficient bulk processing
    preload_reference_data

    # Filter valid points and prepare for bulk import
    valid_points = filter_and_prepare_points

    if valid_points.empty?
      Rails.logger.info "No valid points to import"
      return 0
    end

    # Remove duplicates based on unique constraint
    deduplicated_points = deduplicate_points(valid_points)

    Rails.logger.info "Prepared #{deduplicated_points.size} unique valid points (#{points_data.size - deduplicated_points.size} duplicates/invalid skipped)"

    # Bulk import in batches
    total_created = bulk_import_points(deduplicated_points)

    Rails.logger.info "Points import completed. Created: #{total_created}"
    total_created
  end

  private

  attr_reader :user, :points_data, :imports_lookup, :countries_lookup, :visits_lookup

  def preload_reference_data
    # Pre-load imports for this user
    @imports_lookup = user.imports.index_by { |import|
      [import.name, import.source, import.created_at.to_s]
    }

    # Pre-load all countries for efficient lookup
    @countries_lookup = {}
    Country.all.each do |country|
      # Index by all possible lookup keys
      @countries_lookup[[country.name, country.iso_a2, country.iso_a3]] = country
      @countries_lookup[country.name] = country
    end

    # Pre-load visits for this user
    @visits_lookup = user.visits.index_by { |visit|
      [visit.name, visit.started_at.to_s, visit.ended_at.to_s]
    }
  end

  def filter_and_prepare_points
    valid_points = []
    skipped_count = 0

    points_data.each do |point_data|
      next unless point_data.is_a?(Hash)

      # Skip points with invalid or missing required data
      unless valid_point_data?(point_data)
        skipped_count += 1
        next
      end

      # Prepare point attributes for bulk insert
      prepared_attributes = prepare_point_attributes(point_data)
      unless prepared_attributes
        skipped_count += 1
        next
      end

      valid_points << prepared_attributes
    end

    if skipped_count > 0
      Rails.logger.warn "Skipped #{skipped_count} points with invalid or missing required data"
    end

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
    attributes.symbolize_keys
  rescue StandardError => e
    Rails.logger.error "Failed to prepare point attributes: #{e.message}"
    Rails.logger.error "Point data: #{point_data.inspect}"
    nil
  end

  def resolve_import_reference(attributes, import_reference)
    return unless import_reference.is_a?(Hash)

    import_key = [
      import_reference['name'],
      import_reference['source'],
      import_reference['created_at']
    ]

    import = imports_lookup[import_key]
    attributes['import_id'] = import.id if import
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

    # If still not found, create a new country record
    if country.nil? && country_info['name'].present?
      country = create_missing_country(country_info)
      # Add to lookup cache for subsequent points
      @countries_lookup[country_info['name']] = country
      @countries_lookup[[country.name, country.iso_a2, country.iso_a3]] = country
    end

    attributes['country_id'] = country.id if country
  end

  def create_missing_country(country_info)
    Country.find_or_create_by(name: country_info['name']) do |new_country|
      new_country.iso_a2 = country_info['iso_a2'] || country_info['name'][0..1].upcase
      new_country.iso_a3 = country_info['iso_a3'] || country_info['name'][0..2].upcase
      new_country.geom = "MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))"  # Default geometry
    end
  rescue StandardError => e
    Rails.logger.error "Failed to create missing country: #{e.message}"
    nil
  end

  def resolve_visit_reference(attributes, visit_reference)
    return unless visit_reference.is_a?(Hash)

    visit_key = [
      visit_reference['name'],
      visit_reference['started_at'],
      visit_reference['ended_at']
    ]

    visit = visits_lookup[visit_key]
    attributes['visit_id'] = visit.id if visit
  end

  def deduplicate_points(points)
    points.uniq { |point| [point[:lonlat], point[:timestamp], point[:user_id]] }
  end

  def bulk_import_points(points)
    total_created = 0

    points.each_slice(BATCH_SIZE) do |batch|
      begin
        # Use upsert_all to efficiently bulk insert/update points
        result = Point.upsert_all(
          batch,
          unique_by: %i[lonlat timestamp user_id],
          returning: %w[id],
          on_duplicate: :skip
        )

        batch_created = result.count
        total_created += batch_created

        Rails.logger.debug "Processed batch of #{batch.size} points, created #{batch_created}, total created: #{total_created}"

      rescue StandardError => e
        Rails.logger.error "Failed to process point batch: #{e.message}"
        Rails.logger.error "Batch size: #{batch.size}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(3).join('\n')}"
        # Continue with next batch instead of failing completely
      end
    end

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
    end
  end
end

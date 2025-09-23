# frozen_string_literal: true

class Users::ImportData::Points

  def initialize(user, points_data)
    @user = user
    @points_data = points_data
  end

  def call
    return 0 unless points_data.is_a?(Array)

    Rails.logger.info "Importing #{points_data.size} points for user: #{user.email}"
    Rails.logger.debug "First point sample: #{points_data.first.inspect}"

    preload_reference_data

    valid_points = filter_and_prepare_points

    if valid_points.empty?
      Rails.logger.warn "No valid points to import after filtering"
      Rails.logger.debug "Original points_data size: #{points_data.size}"
      return 0
    end

    deduplicated_points = deduplicate_points(valid_points)

    Rails.logger.info "Prepared #{deduplicated_points.size} unique valid points (#{points_data.size - deduplicated_points.size} duplicates/invalid skipped)"

    total_created = bulk_import_points(deduplicated_points)

    Rails.logger.info "Points import completed. Created: #{total_created}"
    total_created
  end

  private

  attr_reader :user, :points_data, :imports_lookup, :countries_lookup, :visits_lookup

  def batch_size
    @batch_size ||= DawarichSettings.import_batch_size
  end

  def preload_reference_data
    @imports_lookup = {}
    user.imports.each do |import|
      string_key = [import.name, import.source, import.created_at.utc.iso8601]
      integer_key = [import.name, Import.sources[import.source], import.created_at.utc.iso8601]

      @imports_lookup[string_key] = import
      @imports_lookup[integer_key] = import
    end
    Rails.logger.debug "Loaded #{user.imports.size} imports with #{@imports_lookup.size} lookup keys"

    @countries_lookup = {}
    Country.all.each do |country|
      @countries_lookup[[country.name, country.iso_a2, country.iso_a3]] = country
      @countries_lookup[country.name] = country
    end
    Rails.logger.debug "Loaded #{Country.count} countries for lookup"

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

      unless valid_point_data?(point_data)
        skipped_count += 1
        next
      end

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

    Rails.logger.debug "Filtered #{valid_points.size} valid points from #{points_data.size} total"
    valid_points
  end

  def prepare_point_attributes(point_data)
    attributes = point_data.except(
      'created_at',
      'updated_at',
      'import_reference',
      'country_info',
      'visit_reference',
      'country'
    )

    ensure_lonlat_field(attributes, point_data)

    attributes.delete('longitude')
    attributes.delete('latitude')

    attributes['user_id'] = user.id
    attributes['created_at'] = Time.current
    attributes['updated_at'] = Time.current

    resolve_import_reference(attributes, point_data['import_reference'])
    resolve_country_reference(attributes, point_data['country_info'])
    resolve_visit_reference(attributes, point_data['visit_reference'])

    attributes.symbolize_keys
  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to prepare point attributes')

    nil
  end

    def resolve_import_reference(attributes, import_reference)
    return unless import_reference.is_a?(Hash)

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

    country_key = [country_info['name'], country_info['iso_a2'], country_info['iso_a3']]
    country = countries_lookup[country_key]

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

  def normalize_point_keys(points)
    # Return points as-is since upsert_all can handle inconsistent keys
    # This eliminates the expensive hash reconstruction overhead
    points
  end

  def bulk_import_points(points)
    total_created = 0

    points.each_slice(batch_size) do |batch|
      begin
        # Only log every 10th batch to reduce noise
        if (total_created / batch_size) % 10 == 0
          Rails.logger.info "Processed #{total_created} points so far, current batch: #{batch.size}"
        end

        normalized_batch = normalize_point_keys(batch)

        result = Point.upsert_all(
          normalized_batch,
          unique_by: %i[lonlat timestamp user_id],
          returning: %w[id],
          on_duplicate: :skip
        )

        batch_created = result.count
        total_created += batch_created

      rescue StandardError => e
        Rails.logger.error "Failed to process point batch: #{e.message}"
        Rails.logger.error "Batch size: #{batch.size}"
        Rails.logger.error "First point in failed batch: #{batch.first.inspect}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
      end
    end

    total_created
  end

  def valid_point_data?(point_data)
    return false unless point_data.is_a?(Hash)
    return false unless point_data['timestamp'].present?

    has_lonlat = point_data['lonlat'].present? && point_data['lonlat'].is_a?(String) && point_data['lonlat'].start_with?('POINT(')
    has_coordinates = point_data['longitude'].present? && point_data['latitude'].present?

    return false unless has_lonlat || has_coordinates

    true
  rescue StandardError => e
    Rails.logger.debug "Point validation failed: #{e.message} for data: #{point_data.inspect}"
    false
  end

  def ensure_lonlat_field(attributes, point_data)
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
      Time.parse(timestamp).utc.iso8601
    when Time, DateTime
      timestamp.utc.iso8601
    else
      timestamp.to_s
    end
  rescue StandardError => e
    Rails.logger.debug "Failed to normalize timestamp #{timestamp}: #{e.message}"
    timestamp.to_s
  end
end

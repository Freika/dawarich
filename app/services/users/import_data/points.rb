# frozen_string_literal: true

class Users::ImportData::Points
  def initialize(user, points_data)
    @user = user
    @points_data = points_data
  end

  def call
    return 0 unless points_data.is_a?(Array)

    Rails.logger.info "Importing #{points_data.size} points for user: #{user.email}"

    points_created = 0
    skipped_invalid = 0

    points_data.each do |point_data|
      next unless point_data.is_a?(Hash)

      # Skip points with invalid or missing required data
      unless valid_point_data?(point_data)
        skipped_invalid += 1
        next
      end

      # Check if point already exists (match by coordinates, timestamp, and user)
      if point_exists?(point_data)
        next
      end

      # Create new point
      point_record = create_point_record(point_data)
      points_created += 1 if point_record

      if points_created % 1000 == 0
        Rails.logger.debug "Imported #{points_created} points..."
      end
    end

    if skipped_invalid > 0
      Rails.logger.warn "Skipped #{skipped_invalid} points with invalid or missing required data"
    end

    Rails.logger.info "Points import completed. Created: #{points_created}"
    points_created
  end

  private

  attr_reader :user, :points_data

  def point_exists?(point_data)
    return false unless point_data['lonlat'].present? && point_data['timestamp'].present?

    Point.exists?(
      lonlat: point_data['lonlat'],
      timestamp: point_data['timestamp'],
      user_id: user.id
    )
  rescue StandardError => e
    Rails.logger.debug "Error checking if point exists: #{e.message}"
    false
  end

  def create_point_record(point_data)
    point_attributes = prepare_point_attributes(point_data)

    begin
      # Create point and skip the automatic country assignment callback since we're handling it manually
      point = Point.create!(point_attributes)

      # If we have a country assigned via country_info, update the point to set it
      if point_attributes[:country].present?
        point.update_column(:country_id, point_attributes[:country].id)
        point.reload
      end

      point
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create point: #{e.message}"
      Rails.logger.error "Point data: #{point_data.inspect}"
      Rails.logger.error "Prepared attributes: #{point_attributes.inspect}"
      nil
    rescue StandardError => e
      Rails.logger.error "Unexpected error creating point: #{e.message}"
      Rails.logger.error "Point data: #{point_data.inspect}"
      Rails.logger.error "Prepared attributes: #{point_attributes.inspect}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
      nil
    end
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
    ).merge(user: user)

    # Handle lonlat reconstruction if missing (for backward compatibility)
    ensure_lonlat_field(attributes, point_data)

    # Find and assign related records
    assign_import_reference(attributes, point_data['import_reference'])
    assign_country_reference(attributes, point_data['country_info'])
    assign_visit_reference(attributes, point_data['visit_reference'])

    attributes
  end

  def assign_import_reference(attributes, import_reference)
    return unless import_reference.is_a?(Hash)

    import = user.imports.find_by(
      name: import_reference['name'],
      source: import_reference['source'],
      created_at: import_reference['created_at']
    )

    attributes[:import] = import if import
  end

  def assign_country_reference(attributes, country_info)
    return unless country_info.is_a?(Hash)

    # Try to find country by all attributes first
    country = Country.find_by(
      name: country_info['name'],
      iso_a2: country_info['iso_a2'],
      iso_a3: country_info['iso_a3']
    )

    # If not found by all attributes, try to find by name only
    if country.nil? && country_info['name'].present?
      country = Country.find_by(name: country_info['name'])
    end

    # If still not found, create a new country record with minimal data
    if country.nil? && country_info['name'].present?
      country = Country.find_or_create_by(name: country_info['name']) do |new_country|
        new_country.iso_a2 = country_info['iso_a2'] || country_info['name'][0..1].upcase
        new_country.iso_a3 = country_info['iso_a3'] || country_info['name'][0..2].upcase
        new_country.geom = "MULTIPOLYGON (((0 0, 1 0, 1 1, 0 1, 0 0)))"  # Default geometry
      end
    end

    attributes[:country] = country if country
  end

  def assign_visit_reference(attributes, visit_reference)
    return unless visit_reference.is_a?(Hash)

    visit = user.visits.find_by(
      name: visit_reference['name'],
      started_at: visit_reference['started_at'],
      ended_at: visit_reference['ended_at']
    )

    attributes[:visit] = visit if visit
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

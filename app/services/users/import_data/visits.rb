# frozen_string_literal: true

class Users::ImportData::Visits
  def initialize(user, visits_data)
    @user = user
    @visits_data = visits_data
  end

  def call
    return 0 unless visits_data.is_a?(Array)

    Rails.logger.info "Importing #{visits_data.size} visits for user: #{user.email}"

    visits_created = 0

    visits_data.each do |visit_data|
      next unless visit_data.is_a?(Hash)

      existing_visit = find_existing_visit(visit_data)

      if existing_visit
        Rails.logger.debug "Visit already exists: #{visit_data['name']}"
        next
      end

      begin
        visit_record = create_visit_record(visit_data)
        visits_created += 1
        Rails.logger.debug "Created visit: #{visit_record.name}"
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "Failed to create visit: #{visit_data.inspect}, error: #{e.message}"
        ExceptionReporter.call(e, 'Failed to create visit during import')
        next
      rescue StandardError => e
        Rails.logger.error "Unexpected error creating visit: #{visit_data.inspect}, error: #{e.message}"
        ExceptionReporter.call(e, 'Unexpected error during visit import')
        next
      end
    end

    Rails.logger.info "Visits import completed. Created: #{visits_created}"
    visits_created
  end

  private

  attr_reader :user, :visits_data

  def find_existing_visit(visit_data)
    user.visits.find_by(
      name: visit_data['name'],
      started_at: visit_data['started_at'],
      ended_at: visit_data['ended_at']
    )
  end

  def create_visit_record(visit_data)
    visit_attributes = prepare_visit_attributes(visit_data)
    user.visits.create!(visit_attributes)
  end

  def prepare_visit_attributes(visit_data)
    attributes = visit_data.except('place_reference')

    if visit_data['place_reference']
      place = find_or_create_referenced_place(visit_data['place_reference'])
      attributes[:place] = place if place
    end

    attributes
  end

  def find_or_create_referenced_place(place_reference)
    return nil unless place_reference.is_a?(Hash)

    name = place_reference['name']
    latitude = place_reference['latitude']&.to_f
    longitude = place_reference['longitude']&.to_f

    return nil unless name.present? && latitude.present? && longitude.present?

    Rails.logger.debug "Looking for place reference: #{name} at (#{latitude}, #{longitude})"

    # First try exact match (name + coordinates)
    place = Place.where(
      name: name,
      latitude: latitude,
      longitude: longitude
    ).first

    if place
      Rails.logger.debug "Found exact place match for visit: #{name} -> existing place ID #{place.id}"
      return place
    end

    # Try coordinate-only match with close proximity
    place = Place.where(
      "latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?",
      latitude - 0.0001, latitude + 0.0001,
      longitude - 0.0001, longitude + 0.0001
    ).first

    if place
      Rails.logger.debug "Found nearby place match for visit: #{name} -> #{place.name} (ID: #{place.id})"
      return place
    end

    # If no match found, create the place to ensure visit import succeeds
    # This handles cases where places weren't imported in the places phase
    Rails.logger.info "Creating missing place during visit import: #{name} at (#{latitude}, #{longitude})"

    begin
      place = Place.create!(
        name: name,
        latitude: latitude,
        longitude: longitude,
        lonlat: "POINT(#{longitude} #{latitude})",
        source: place_reference['source'] || 'manual'
      )

      Rails.logger.debug "Created missing place for visit: #{place.name} (ID: #{place.id})"
      place
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create missing place: #{place_reference.inspect}, error: #{e.message}"
      ExceptionReporter.call(e, 'Failed to create missing place during visit import')
      nil
    end
  end
end

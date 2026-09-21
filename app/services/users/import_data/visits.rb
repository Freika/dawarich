# frozen_string_literal: true

class Users::ImportData::Visits
  def initialize(user, visits_data, legacy_area_place_references: {}, legacy_area_places_by_name: {})
    @user = user
    @visits_data = visits_data
    @legacy_area_place_references = legacy_area_place_references
    @legacy_area_places_by_name = legacy_area_places_by_name
  end

  def call
    return 0 unless visits_data.is_a?(Array)

    Rails.logger.info "Importing #{visits_data.size} visits for user: #{user.email}"

    visits_created = 0

    visits_data.each do |visit_data|
      next unless visit_data.is_a?(Hash)

      begin
        visit_attributes = prepare_visit_attributes(visit_data)
        existing_visit = find_existing_visit(visit_attributes)

        if existing_visit
          Rails.logger.debug "Visit already exists: #{visit_data['name']}"
          next
        end

        visit_record = create_visit_record(visit_attributes)
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

  attr_reader :user, :visits_data, :legacy_area_place_references, :legacy_area_places_by_name

  def find_existing_visit(attributes)
    user.visits.find_by(
      name: attributes['name'],
      location_label: attributes['location_label'],
      started_at: attributes['started_at'],
      ended_at: attributes['ended_at'],
      place_id: attributes[:place]&.id || attributes['place_id']
    )
  end

  def create_visit_record(attributes)
    ActiveRecord::Base.transaction(requires_new: true) { user.visits.create!(attributes) }
  end

  def prepare_visit_attributes(visit_data)
    attributes = visit_data.except('place_reference', 'area_id')
    legacy_area_id = visit_data['area_id']
    attributes['location_label'] ||= visit_data['name'] if legacy_area_id.present?

    reference = visit_data['place_reference'] || legacy_place_reference(visit_data)
    if reference
      place = find_or_create_referenced_place(reference)
      attributes[:place] = place if place
    end

    attributes
  end

  def legacy_place_reference(visit_data)
    legacy_id = visit_data['area_id']
    return if legacy_id.blank?

    legacy_area_place_references[legacy_id.to_s] ||
      legacy_area_places_by_name[visit_data['location_label'].presence&.strip&.downcase] ||
      legacy_area_places_by_name[visit_data['name'].presence&.strip&.downcase]
  end

  def find_or_create_referenced_place(place_reference)
    return nil unless place_reference.is_a?(Hash)

    name = place_reference['name']
    latitude = place_reference['latitude']&.to_f
    longitude = place_reference['longitude']&.to_f

    return nil unless name.present? && latitude.present? && longitude.present?

    Rails.logger.debug "Looking for place reference: #{name} at (#{latitude}, #{longitude})"

    place = user.places.find_by(
      name: name,
      latitude: latitude,
      longitude: longitude
    )

    if place
      Rails.logger.debug "Found exact place match for visit: #{name} -> existing place ID #{place.id}"
      return place
    end

    place = user.places
                .where('LOWER(BTRIM(name)) = ?', name.to_s.strip.downcase)
                .near([latitude, longitude], 50, :m)
                .order(:id)
                .first

    if place
      Rails.logger.debug "Found nearby place match for visit: #{name} -> #{place.name} (ID: #{place.id})"
      return place
    end

    Rails.logger.info "Creating missing place during visit import: #{name} at (#{latitude}, #{longitude})"

    begin
      place = user.places.create!(
        name: name,
        latitude: latitude,
        longitude: longitude,
        lonlat: "POINT(#{longitude} #{latitude})",
        source: place_reference['source'] || 'manual',
        visit_radius: Place.normalize_visit_radius(place_reference['visit_radius'])
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

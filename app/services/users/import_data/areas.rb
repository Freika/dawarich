# frozen_string_literal: true

# Compatibility reader for backups that still contain Areas. New imports do
# not recreate the retired domain entity: each legacy Area becomes (or reuses)
# a canonical Place and its radius becomes the Place's Visit Radius.
class Users::ImportData::Areas
  MATCH_RADIUS_METERS = 50

  attr_reader :place_references_by_id, :place_references_by_name

  def initialize(user, areas_data)
    @user = user
    @areas_data = areas_data
    @place_references_by_id = {}
    @place_references_by_name = {}
  end

  def call
    return 0 unless areas_data.is_a?(Array)

    Rails.logger.info "Importing #{areas_data.size} legacy areas as Places for user: #{user.email}"

    created = areas_data.count { |area_data| import_area(area_data) == :created }

    Rails.logger.info "Legacy Areas import completed. Places created: #{created}"
    created
  end

  private

  attr_reader :user, :areas_data

  def import_area(area_data)
    return :skipped unless valid_area_data?(area_data)

    name = area_data['name'].to_s.strip
    latitude = area_data['latitude'].to_f
    longitude = area_data['longitude'].to_f
    radius = positive_radius(area_data['radius'])
    candidates = matching_places(name, latitude, longitude)

    # Multiple same-name candidates are deliberately not guessed between.
    place = candidates.one? ? candidates.first : create_place(name, latitude, longitude, radius)
    place.update!(visit_radius: [place.visit_radius, radius].max) if place.visit_radius < radius
    remember_reference(area_data, place)

    place.previously_new_record? ? :created : :reused
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "Skipped invalid legacy Area during import: #{e.record.errors.full_messages.join(', ')}"
    :skipped
  end

  def matching_places(name, latitude, longitude)
    user.places
        .where('LOWER(BTRIM(name)) = ?', normalize(name))
        .near([latitude, longitude], MATCH_RADIUS_METERS, :m)
        .order(:id)
        .to_a
  end

  def create_place(name, latitude, longitude, radius)
    place = user.places.build(
      name: name,
      latitude: latitude,
      longitude: longitude,
      visit_radius: radius,
      source: :manual
    )
    place.user_named = true
    place.skip_suggested_visit_reattribution = true
    place.save!
    place
  end

  def remember_reference(area_data, place)
    reference = {
      'name' => place.name,
      'latitude' => place.lat.to_s,
      'longitude' => place.lon.to_s,
      'source' => place.source,
      'visit_radius' => place.visit_radius
    }

    legacy_id = area_data['id'] || area_data['area_id']
    place_references_by_id[legacy_id.to_s] = reference if legacy_id.present?

    normalized_name = normalize(place.name)
    if place_references_by_name.key?(normalized_name)
      place_references_by_name.delete(normalized_name)
    else
      place_references_by_name[normalized_name] = reference
    end
  end

  def valid_area_data?(area_data)
    area_data.is_a?(Hash) && area_data['name'].present? &&
      area_data['latitude'].present? && area_data['longitude'].present?
  end

  def positive_radius(radius)
    value = radius.to_i
    value.positive? ? value : 50
  end

  def normalize(name)
    name.to_s.strip.downcase
  end
end

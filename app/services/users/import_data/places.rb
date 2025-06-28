# frozen_string_literal: true

class Users::ImportData::Places
  def initialize(user, places_data)
    @user = user
    @places_data = places_data
  end

  def call
    return 0 unless places_data.is_a?(Array)

    Rails.logger.info "Importing #{places_data.size} places for user: #{user.email}"

    places_created = 0

    places_data.each do |place_data|
      next unless place_data.is_a?(Hash)

      # Find or create place by name and coordinates
      place = find_or_create_place(place_data)
      places_created += 1 if place&.respond_to?(:previously_new_record?) && place.previously_new_record?
    end

    Rails.logger.info "Places import completed. Created: #{places_created}"
    places_created
  end

  private

  attr_reader :user, :places_data

  def find_or_create_place(place_data)
    name = place_data['name']
    latitude = place_data['latitude']&.to_f
    longitude = place_data['longitude']&.to_f

    # Skip if essential data is missing
    unless name.present? && latitude.present? && longitude.present?
      Rails.logger.debug "Skipping place with missing required data: #{place_data.inspect}"
      return nil
    end

    # Try to find existing place by name first, then by coordinates
    existing_place = Place.find_by(name: name)

    # If no place with same name, check by coordinates
    unless existing_place
      existing_place = Place.where(latitude: latitude, longitude: longitude).first
    end

    if existing_place
      Rails.logger.debug "Place already exists: #{name}"
      existing_place.define_singleton_method(:previously_new_record?) { false }
      return existing_place
    end

    # Create new place with lonlat point
    place_attributes = place_data.except('created_at', 'updated_at', 'latitude', 'longitude')
    place_attributes['lonlat'] = "POINT(#{longitude} #{latitude})"
    place_attributes['latitude'] = latitude
    place_attributes['longitude'] = longitude
    # Remove any user reference since Place doesn't belong to user directly
    place_attributes.delete('user')

    begin
      place = Place.create!(place_attributes)
      place.define_singleton_method(:previously_new_record?) { true }
      Rails.logger.debug "Created place: #{place.name}"

      place
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create place: #{e.message}"
      nil
    end
  end
end

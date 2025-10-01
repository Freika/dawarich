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

    # Preload all existing places to avoid N+1 queries
    @existing_places_cache = load_existing_places

    places_data.each do |place_data|
      next unless place_data.is_a?(Hash)

      place = find_or_create_place_for_import(place_data)
      places_created += 1 if place&.respond_to?(:previously_new_record?) && place.previously_new_record?
    end

    Rails.logger.info "Places import completed. Created: #{places_created}"
    places_created
  end

  private

  attr_reader :user, :places_data

  def load_existing_places
    # Extract all coordinates from places_data to preload relevant places
    coordinates = places_data.select do |pd|
      pd.is_a?(Hash) && pd['name'].present? && pd['latitude'].present? && pd['longitude'].present?
    end.map { |pd| { name: pd['name'], lat: pd['latitude'].to_f, lon: pd['longitude'].to_f } }

    return {} if coordinates.empty?

    # Build a hash for quick lookup: "name_lat_lon" => place
    cache = {}

    # Build OR conditions using Arel to fetch all matching places in a single query
    arel_table = Place.arel_table
    conditions = coordinates.map do |coord|
      arel_table[:name].eq(coord[:name])
                       .and(arel_table[:latitude].eq(coord[:lat]))
                       .and(arel_table[:longitude].eq(coord[:lon]))
    end.reduce { |result, condition| result.or(condition) }

    # Fetch all matching places in a single query
    Place.where(conditions).find_each do |place|
      cache_key = place_cache_key(place.name, place.latitude, place.longitude)
      cache[cache_key] = place
    end

    cache
  end

  def place_cache_key(name, latitude, longitude)
    "#{name}_#{latitude}_#{longitude}"
  end

  def find_or_create_place_for_import(place_data)
    name = place_data['name']
    latitude = place_data['latitude']&.to_f
    longitude = place_data['longitude']&.to_f

    unless name.present? && latitude.present? && longitude.present?
      Rails.logger.debug "Skipping place with missing required data: #{place_data.inspect}"
      return nil
    end

    Rails.logger.debug "Processing place for import: #{name} at (#{latitude}, #{longitude})"

    # During import, we prioritize data integrity for the importing user
    # First try exact match (name + coordinates) from cache
    cache_key = place_cache_key(name, latitude, longitude)
    existing_place = @existing_places_cache[cache_key]

    if existing_place
      Rails.logger.debug "Found exact place match: #{name} at (#{latitude}, #{longitude}) -> existing place ID #{existing_place.id}"
      existing_place.define_singleton_method(:previously_new_record?) { false }
      return existing_place
    end

    Rails.logger.debug "No exact match found for #{name} at (#{latitude}, #{longitude}). Creating new place."

    # If no exact match, create a new place to ensure data integrity
    # This prevents data loss during import even if similar places exist
    place_attributes = place_data.except('created_at', 'updated_at', 'latitude', 'longitude')
    place_attributes['lonlat'] = "POINT(#{longitude} #{latitude})"
    place_attributes['latitude'] = latitude
    place_attributes['longitude'] = longitude
    place_attributes.delete('user')

    Rails.logger.debug "Creating place with attributes: #{place_attributes.inspect}"

    begin
      place = Place.create!(place_attributes)
      place.define_singleton_method(:previously_new_record?) { true }
      Rails.logger.debug "Created place during import: #{place.name} (ID: #{place.id})"

      # Add to cache for subsequent lookups
      @existing_places_cache[cache_key] = place

      place
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create place: #{place_data.inspect}, error: #{e.message}"
      nil
    end
  end
end

# frozen_string_literal: true

class Users::ImportData::Places
  BATCH_SIZE = 5000

  def initialize(user, places_data = nil, batch_size: BATCH_SIZE, logger: Rails.logger)
    @user = user
    @places_data = places_data
    @batch_size = batch_size
    @logger = logger
    @buffer = []
    @created = 0
  end

  def call
    return 0 unless places_data.respond_to?(:each)

    logger.info "Importing #{collection_description(places_data)} places for user: #{user.email}"

    enumerate(places_data) do |place_data|
      add(place_data)
    end

    finalize
  end

  def add(place_data)
    return unless place_data.is_a?(Hash)

    @buffer << place_data
    flush_batch if @buffer.size >= batch_size
  end

  def finalize
    flush_batch
    logger.info "Places import completed. Created: #{@created}"
    @created
  end

  private

  attr_reader :user, :places_data, :batch_size, :logger

  def enumerate(collection, &block)
    collection.each(&block)
  end

  def collection_description(collection)
    return collection.size if collection.respond_to?(:size)

    'streamed'
  end

  def flush_batch
    return if @buffer.empty?

    logger.debug "Processing places batch of #{@buffer.size}"
    @buffer.each do |place_data|
      place = find_or_create_place_for_import(place_data)
      @created += 1 if place&.respond_to?(:previously_new_record?) && place.previously_new_record?
    end

    @buffer.clear
  end

  def find_or_create_place_for_import(place_data)
    name = place_data['name']
    latitude = place_data['latitude']&.to_f
    longitude = place_data['longitude']&.to_f

    unless name.present? && latitude.present? && longitude.present?
      logger.debug "Skipping place with missing required data: #{place_data.inspect}"
      return nil
    end

    logger.debug "Processing place for import: #{name} at (#{latitude}, #{longitude})"

    existing_place = Place.where(
      name: name,
      latitude: latitude,
      longitude: longitude
    ).first

    if existing_place
      logger.debug "Found exact place match: #{name} at (#{latitude}, #{longitude}) -> existing place ID #{existing_place.id}"
      existing_place.define_singleton_method(:previously_new_record?) { false }
      return existing_place
    end

    logger.debug "No exact match found for #{name} at (#{latitude}, #{longitude}). Creating new place."

    place_attributes = place_data.except('created_at', 'updated_at', 'latitude', 'longitude')
    place_attributes['lonlat'] = "POINT(#{longitude} #{latitude})"
    place_attributes['latitude'] = latitude
    place_attributes['longitude'] = longitude
    place_attributes.delete('user')

    logger.debug "Creating place with attributes: #{place_attributes.inspect}"

    begin
      place = Place.create!(place_attributes)
      place.define_singleton_method(:previously_new_record?) { true }
      logger.debug "Created place during import: #{place.name} (ID: #{place.id})"

      place
    rescue ActiveRecord::RecordInvalid => e
      logger.error "Failed to create place: #{place_data.inspect}, error: #{e.message}"
      nil
    end
  end
end

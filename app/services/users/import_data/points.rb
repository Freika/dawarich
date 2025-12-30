# frozen_string_literal: true

require 'time'

class Users::ImportData::Points
  BATCH_SIZE = 5000

  def initialize(user, points_data = nil, batch_size: BATCH_SIZE, logger: Rails.logger)
    @user = user
    @points_data = points_data
    @batch_size = batch_size
    @logger = logger

    @buffer = []
    @total_created = 0
    @processed_count = 0
    @skipped_count = 0
    @preloaded = false

    @imports_lookup = {}
    @countries_lookup = {}
    @visits_lookup = {}
  end

  def call
    return 0 unless points_data.respond_to?(:each)

    logger.info "Importing #{collection_description(points_data)} points for user: #{user.email}"

    enumerate(points_data) do |point_data|
      add(point_data)
    end

    finalize
  end

  # Allows streamed usage by pushing a single point at a time.
  def add(point_data)
    preload_reference_data unless @preloaded

    if valid_point_data?(point_data)
      prepared_attributes = prepare_point_attributes(point_data)

      if prepared_attributes
        @buffer << prepared_attributes
        @processed_count += 1

        flush_batch if @buffer.size >= batch_size
      else
        @skipped_count += 1
      end
    else
      @skipped_count += 1
      logger.debug "Skipped point: invalid data - #{point_data.inspect}"
    end
  end

  def finalize
    preload_reference_data unless @preloaded
    flush_batch

    logger.info "Points import completed. Created: #{@total_created}. Processed #{@processed_count} valid points, skipped #{@skipped_count}."
    @total_created
  end

  private

  attr_reader :user, :points_data, :batch_size, :logger, :imports_lookup, :countries_lookup, :visits_lookup

  def enumerate(collection, &block)
    collection.each(&block)
  end

  def collection_description(collection)
    return collection.size if collection.respond_to?(:size)

    'streamed'
  end

  def flush_batch
    return if @buffer.empty?

    logger.debug "Processing batch of #{@buffer.size} points"
    logger.debug "First point in batch: #{@buffer.first.inspect}"

    normalized_batch = normalize_point_keys(@buffer)

    begin
      result = Point.upsert_all(
        normalized_batch,
        unique_by: %i[lonlat timestamp user_id],
        returning: %w[id],
        on_duplicate: :skip
      )

      batch_created = result&.count.to_i
      @total_created += batch_created

      logger.debug "Processed batch of #{@buffer.size} points, created #{batch_created}, total created: #{@total_created}"
    rescue StandardError => e
      logger.error "Failed to process point batch: #{e.message}"
      logger.error "Batch size: #{@buffer.size}"
      logger.error "First point in failed batch: #{@buffer.first.inspect}"
      logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
    ensure
      @buffer.clear
    end
  end

  def preload_reference_data
    return if @preloaded

    logger.debug 'Preloading reference data for points import'

    @imports_lookup = {}
    user.imports.reload.each do |import|
      string_key = [import.name, import.source, import.created_at.utc.iso8601]
      integer_key = [import.name, Import.sources[import.source], import.created_at.utc.iso8601]

      @imports_lookup[string_key] = import
      @imports_lookup[integer_key] = import
    end
    logger.debug "Loaded #{user.imports.size} imports with #{@imports_lookup.size} lookup keys"

    @countries_lookup = {}
    Country.all.each do |country|
      @countries_lookup[[country.name, country.iso_a2, country.iso_a3]] = country
      @countries_lookup[country.name] = country
    end
    logger.debug "Loaded #{Country.count} countries for lookup"

    @visits_lookup = user.visits.reload.index_by do |visit|
      [visit.name, visit.started_at.utc.iso8601, visit.ended_at.utc.iso8601]
    end
    logger.debug "Loaded #{@visits_lookup.size} visits for lookup"

    @preloaded = true
  end

  def normalize_point_keys(points)
    all_keys = points.flat_map(&:keys).uniq

    points.map do |point|
      all_keys.each_with_object({}) do |key, normalized|
        normalized[key] = point[key]
      end
    end
  end

  def valid_point_data?(point_data)
    return false unless point_data.is_a?(Hash)
    return false unless point_data['timestamp'].present?

    has_lonlat = point_data['lonlat'].present? && point_data['lonlat'].is_a?(String) && point_data['lonlat'].start_with?('POINT(')
    has_coordinates = point_data['longitude'].present? && point_data['latitude'].present?

    has_lonlat || has_coordinates
  rescue StandardError => e
    logger.debug "Point validation failed: #{e.message} for data: #{point_data.inspect}"
    false
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

    result = attributes.symbolize_keys

    logger.debug "Prepared point attributes: #{result.slice(:lonlat, :timestamp, :import_id, :country_id, :visit_id)}"
    result
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
      logger.debug "Resolved import reference: #{import_reference['name']} -> #{import.id}"
    else
      logger.debug "Import not found for reference: #{import_reference.inspect}"
      logger.debug "Available imports: #{imports_lookup.keys.inspect}"
    end
  end

  def resolve_country_reference(attributes, country_info)
    return unless country_info.is_a?(Hash)

    country_key = [country_info['name'], country_info['iso_a2'], country_info['iso_a3']]
    country = countries_lookup[country_key]

    country = countries_lookup[country_info['name']] if country.nil? && country_info['name'].present?

    if country
      attributes['country_id'] = country.id
      logger.debug "Resolved country reference: #{country_info['name']} -> #{country.id}"
    else
      logger.debug "Country not found for: #{country_info.inspect}"
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
      logger.debug "Resolved visit reference: #{visit_reference['name']} -> #{visit.id}"
    else
      logger.debug "Visit not found for reference: #{visit_reference.inspect}"
      logger.debug "Available visits: #{visits_lookup.keys.inspect}"
    end
  end

  def ensure_lonlat_field(attributes, point_data)
    return unless attributes['lonlat'].blank? && point_data['longitude'].present? && point_data['latitude'].present?

    longitude = point_data['longitude'].to_f
    latitude = point_data['latitude'].to_f
    attributes['lonlat'] = "POINT(#{longitude} #{latitude})"
    logger.debug "Reconstructed lonlat: #{attributes['lonlat']}"
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
    logger.debug "Failed to normalize timestamp #{timestamp}: #{e.message}"
    timestamp.to_s
  end
end

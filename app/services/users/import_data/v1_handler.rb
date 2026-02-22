# frozen_string_literal: true

require 'oj'

# Users::ImportData::V1Handler - Handles import of v1 (legacy) format archives
#
# V1 format structure:
# export.zip/
# ├── data.json        # Single JSON file with all data
# └── files/           # Attached files
#
# The data.json contains a single JSON object with all entity arrays:
# {
#   "counts": {...},
#   "settings": {...},
#   "areas": [...],
#   "imports": [...],
#   "exports": [...],
#   "trips": [...],
#   "stats": [...],
#   "notifications": [...],
#   "points": [...],
#   "visits": [...],
#   "places": [...]
# }

class Users::ImportData::V1Handler
  STREAM_BATCH_SIZE = 5000
  STREAMED_SECTIONS = %w[places visits points].freeze

  def initialize(user, import_directory, import_stats)
    @user = user
    @import_directory = import_directory
    @import_stats = import_stats
    @expected_counts = nil
  end

  def process
    Rails.logger.info "Processing v1 format archive for user: #{user.email}"

    json_path = import_directory.join('data.json')
    raise StandardError, 'Data file not found in archive: data.json' unless File.exist?(json_path)

    initialize_stream_state

    handler = ::JsonStreamHandler.new(self)
    parser = Oj::Parser.new(:saj, handler: handler)

    File.open(json_path, 'rb') do |io|
      parser.load(io)
    end

    finalize_stream_processing
  rescue Oj::ParseError => e
    raise StandardError, "Invalid JSON format in data file: #{e.message}"
  rescue IOError => e
    raise StandardError, "Failed to read JSON data: #{e.message}"
  end

  attr_reader :expected_counts

  # Called by JsonStreamHandler for non-streamed sections
  def handle_section(key, value)
    case key
    when 'counts'
      @expected_counts = value if value.is_a?(Hash)
      Rails.logger.info "Expected entity counts from export: #{@expected_counts}" if @expected_counts
    when 'settings'
      import_settings(value) if value.present?
    when 'areas'
      import_areas(value)
    when 'imports'
      import_imports(value)
    when 'exports'
      import_exports(value)
    when 'trips'
      import_trips(value)
    when 'stats'
      import_stats_section(value)
    when 'notifications'
      import_notifications(value)
    else
      Rails.logger.debug "Unhandled non-stream section #{key}" unless STREAMED_SECTIONS.include?(key)
    end
  end

  # Called by JsonStreamHandler for streamed sections (places, visits, points)
  def handle_stream_value(section, value)
    case section
    when 'places'
      queue_place_for_import(value)
    when 'visits'
      append_to_stream(:visits, value)
    when 'points'
      append_to_stream(:points, value)
    else
      Rails.logger.debug "Received stream value for unknown section #{section}"
    end
  end

  # Called by JsonStreamHandler when a streamed section ends
  def finish_stream(section)
    case section
    when 'places'
      flush_places_batch
    when 'visits'
      close_stream_writer(:visits)
    when 'points'
      close_stream_writer(:points)
    end
  end

  private

  attr_reader :user, :import_directory, :import_stats

  def initialize_stream_state
    @places_batch = []
    @stream_writers = {}
    @stream_temp_paths = {}
  end

  def finalize_stream_processing
    flush_places_batch
    close_stream_writer(:visits)
    close_stream_writer(:points)

    process_visits_stream
    process_points_stream

    Rails.logger.info "V1 data import completed. Stats: #{import_stats}"
  end

  def queue_place_for_import(place_data)
    return unless place_data.is_a?(Hash)

    @places_batch << place_data

    return unless @places_batch.size >= STREAM_BATCH_SIZE

    import_places_batch(@places_batch)
    @places_batch.clear
  end

  def flush_places_batch
    return if @places_batch.blank?

    import_places_batch(@places_batch)
    @places_batch.clear
  end

  def import_places_batch(batch)
    Rails.logger.debug "Importing places batch of size #{batch.size}"
    places_created = Users::ImportData::Places.new(user, batch.dup).call.to_i
    import_stats[:places_created] += places_created
  end

  def append_to_stream(section, value)
    return unless value

    writer = stream_writer(section)
    writer.puts(Oj.dump(value, mode: :compat))
  end

  def stream_writer(section)
    @stream_writers[section] ||= begin
      path = stream_temp_path(section)
      Rails.logger.debug "Creating stream buffer for #{section} at #{path}"
      File.open(path, 'w')
    end
  end

  def stream_temp_path(section)
    @stream_temp_paths[section] ||= import_directory.join("stream_#{section}.ndjson")
  end

  def close_stream_writer(section)
    @stream_writers[section]&.close
  ensure
    @stream_writers.delete(section)
  end

  def process_visits_stream
    path = @stream_temp_paths[:visits]
    return unless path&.exist?

    Rails.logger.info 'Importing visits from streamed buffer'

    batch = []
    File.foreach(path) do |line|
      line = line.strip
      next if line.blank?

      batch << Oj.load(line)
      if batch.size >= STREAM_BATCH_SIZE
        import_visits_batch(batch)
        batch = []
      end
    end

    import_visits_batch(batch) if batch.any?
  end

  def import_visits_batch(batch)
    visits_created = Users::ImportData::Visits.new(user, batch).call.to_i
    import_stats[:visits_created] += visits_created
  end

  def process_points_stream
    path = @stream_temp_paths[:points]
    return unless path&.exist?

    Rails.logger.info 'Importing points from streamed buffer'

    importer = Users::ImportData::Points.new(user, nil, batch_size: STREAM_BATCH_SIZE)
    File.foreach(path) do |line|
      line = line.strip
      next if line.blank?

      importer.add(Oj.load(line))
    end

    import_stats[:points_created] = importer.finalize.to_i
  end

  def import_settings(settings_data)
    Rails.logger.debug "Importing settings: #{settings_data.inspect}"
    Users::ImportData::Settings.new(user, settings_data).call
    import_stats[:settings_updated] = true
  end

  def import_areas(areas_data)
    Rails.logger.debug "Importing #{areas_data&.size || 0} areas"
    areas_created = Users::ImportData::Areas.new(user, areas_data).call.to_i
    import_stats[:areas_created] += areas_created
  end

  def import_imports(imports_data)
    Rails.logger.debug "Importing #{imports_data&.size || 0} imports"
    imports_created, files_restored = Users::ImportData::Imports.new(
      user, imports_data, import_directory.join('files')
    ).call
    import_stats[:imports_created] += imports_created.to_i
    import_stats[:files_restored] += files_restored.to_i
  end

  def import_exports(exports_data)
    Rails.logger.debug "Importing #{exports_data&.size || 0} exports"
    exports_created, files_restored = Users::ImportData::Exports.new(
      user, exports_data, import_directory.join('files')
    ).call
    import_stats[:exports_created] += exports_created.to_i
    import_stats[:files_restored] += files_restored.to_i
  end

  def import_trips(trips_data)
    Rails.logger.debug "Importing #{trips_data&.size || 0} trips"
    trips_created = Users::ImportData::Trips.new(user, trips_data).call.to_i
    import_stats[:trips_created] += trips_created
  end

  def import_stats_section(stats_data)
    Rails.logger.debug "Importing #{stats_data&.size || 0} stats"
    stats_created = Users::ImportData::Stats.new(user, stats_data).call.to_i
    import_stats[:stats_created] += stats_created
  end

  def import_notifications(notifications_data)
    Rails.logger.debug "Importing #{notifications_data&.size || 0} notifications"
    notifications_created = Users::ImportData::Notifications.new(user, notifications_data).call.to_i
    import_stats[:notifications_created] += notifications_created
  end
end

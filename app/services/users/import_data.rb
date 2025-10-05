# frozen_string_literal: true

require 'zip'
require 'oj'

# Users::ImportData - Imports complete user data from exported archive
#
# This service processes a ZIP archive created by Users::ExportData and recreates
# the user's data with preserved relationships. The import follows a specific order
# to handle foreign key dependencies:
#
# 1. Settings (applied directly to user)
# 2. Areas (standalone user data)
# 3. Places (referenced by visits)
# 4. Imports (including file attachments)
# 5. Exports (including file attachments)
# 6. Trips (standalone user data)
# 7. Stats (standalone user data)
# 8. Notifications (standalone user data)
# 9. Visits (references places)
# 10. Points (references imports, countries, visits)
#
# Files are restored to their original locations and properly attached to records.

class Users::ImportData
  STREAM_BATCH_SIZE = 1000
  STREAMED_SECTIONS = %w[places visits points].freeze

  def initialize(user, archive_path)
    @user = user
    @archive_path = archive_path
    @import_stats = {
      settings_updated: false,
      areas_created: 0,
      places_created: 0,
      imports_created: 0,
      exports_created: 0,
      trips_created: 0,
      stats_created: 0,
      notifications_created: 0,
      visits_created: 0,
      points_created: 0,
      files_restored: 0
    }
  end

  def import
    @import_directory = Rails.root.join('tmp', "import_#{user.email.gsub(/[^0-9A-Za-z._-]/, '_')}_#{Time.current.to_i}")
    FileUtils.mkdir_p(@import_directory)

    ActiveRecord::Base.transaction do
      extract_archive
      process_archive_data
      create_success_notification

      @import_stats
    end
  rescue StandardError => e
    ExceptionReporter.call(e, 'Data import failed')
    create_failure_notification(e)
    raise e
  ensure
    cleanup_temporary_files(@import_directory) if @import_directory&.exist?
  end

  private

  attr_reader :user, :archive_path, :import_stats

  def extract_archive
    Rails.logger.info "Extracting archive: #{archive_path}"

    Zip::File.open(archive_path) do |zip_file|
      zip_file.each do |entry|
        next if entry.directory?

        sanitized_name = sanitize_zip_entry_name(entry.name)
        next if sanitized_name.nil?

        extraction_path = File.expand_path(File.join(@import_directory, sanitized_name))
        safe_import_dir = File.expand_path(@import_directory) + File::SEPARATOR
        unless extraction_path.start_with?(safe_import_dir) || extraction_path == File.expand_path(@import_directory)
          Rails.logger.warn "Skipping potentially malicious ZIP entry: #{entry.name} (would extract to #{extraction_path})"
          next
        end

        Rails.logger.debug "Extracting #{entry.name} to #{extraction_path}"

        FileUtils.mkdir_p(File.dirname(extraction_path))
        entry.extract(sanitized_name, destination_directory: @import_directory)
      end
    end
  end

  def sanitize_zip_entry_name(entry_name)
    sanitized = entry_name.gsub(%r{^[/\\]+}, '')

    if sanitized.include?('..') || sanitized.start_with?('/') || sanitized.start_with?('\\')
      Rails.logger.warn "Rejecting potentially malicious ZIP entry name: #{entry_name}"
      return nil
    end

    if Pathname.new(sanitized).absolute?
      Rails.logger.warn "Rejecting absolute path in ZIP entry: #{entry_name}"
      return nil
    end

    sanitized
  end

  def process_archive_data
    Rails.logger.info "Starting data import for user: #{user.email}"

    json_path = @import_directory.join('data.json')
    unless File.exist?(json_path)
      raise StandardError, 'Data file not found in archive: data.json'
    end

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

  def initialize_stream_state
    @expected_counts = nil
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

    Rails.logger.info "Data import completed. Stats: #{@import_stats}"

    validate_import_completeness(@expected_counts) if @expected_counts.present?
  end

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
      import_stats(value)
    when 'notifications'
      import_notifications(value)
    else
      Rails.logger.debug "Unhandled non-stream section #{key}" unless STREAMED_SECTIONS.include?(key)
    end
  end

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

  def queue_place_for_import(place_data)
    return unless place_data.is_a?(Hash)

    @places_batch << place_data
    if @places_batch.size >= STREAM_BATCH_SIZE
      import_places_batch(@places_batch)
      @places_batch.clear
    end
  end

  def flush_places_batch
    return if @places_batch.blank?

    import_places_batch(@places_batch)
    @places_batch.clear
  end

  def import_places_batch(batch)
    Rails.logger.debug "Importing places batch of size #{batch.size}"
    places_created = Users::ImportData::Places.new(user, batch.dup).call.to_i
    @import_stats[:places_created] += places_created
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
    @stream_temp_paths[section] ||= @import_directory.join("stream_#{section}.ndjson")
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
    @import_stats[:visits_created] += visits_created
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

    @import_stats[:points_created] = importer.finalize.to_i
  end

  def import_settings(settings_data)
    Rails.logger.debug "Importing settings: #{settings_data.inspect}"
    Users::ImportData::Settings.new(user, settings_data).call
    @import_stats[:settings_updated] = true
  end

  def import_areas(areas_data)
    Rails.logger.debug "Importing #{areas_data&.size || 0} areas"
    areas_created = Users::ImportData::Areas.new(user, areas_data).call.to_i
    @import_stats[:areas_created] += areas_created
  end

  def import_imports(imports_data)
    Rails.logger.debug "Importing #{imports_data&.size || 0} imports"
    imports_created, files_restored = Users::ImportData::Imports.new(user, imports_data, @import_directory.join('files')).call
    @import_stats[:imports_created] += imports_created.to_i
    @import_stats[:files_restored] += files_restored.to_i
  end

  def import_exports(exports_data)
    Rails.logger.debug "Importing #{exports_data&.size || 0} exports"
    exports_created, files_restored = Users::ImportData::Exports.new(user, exports_data, @import_directory.join('files')).call
    @import_stats[:exports_created] += exports_created.to_i
    @import_stats[:files_restored] += files_restored.to_i
  end

  def import_trips(trips_data)
    Rails.logger.debug "Importing #{trips_data&.size || 0} trips"
    trips_created = Users::ImportData::Trips.new(user, trips_data).call.to_i
    @import_stats[:trips_created] += trips_created
  end

  def import_stats(stats_data)
    Rails.logger.debug "Importing #{stats_data&.size || 0} stats"
    stats_created = Users::ImportData::Stats.new(user, stats_data).call.to_i
    @import_stats[:stats_created] += stats_created
  end

  def import_notifications(notifications_data)
    Rails.logger.debug "Importing #{notifications_data&.size || 0} notifications"
    notifications_created = Users::ImportData::Notifications.new(user, notifications_data).call.to_i
    @import_stats[:notifications_created] += notifications_created
  end

  def cleanup_temporary_files(import_directory)
    return unless File.directory?(import_directory)

    Rails.logger.info "Cleaning up temporary import directory: #{import_directory}"
    FileUtils.rm_rf(import_directory)
  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to cleanup temporary files')
  end

  def create_success_notification
    summary = "#{@import_stats[:points_created]} points, " \
      "#{@import_stats[:visits_created]} visits, " \
      "#{@import_stats[:places_created]} places, " \
      "#{@import_stats[:trips_created]} trips, " \
      "#{@import_stats[:areas_created]} areas, " \
      "#{@import_stats[:imports_created]} imports, " \
      "#{@import_stats[:exports_created]} exports, " \
      "#{@import_stats[:stats_created]} stats, " \
      "#{@import_stats[:files_restored]} files restored, " \
      "#{@import_stats[:notifications_created]} notifications"

    ::Notifications::Create.new(
      user: user,
      title: 'Data import completed',
      content: "Your data has been imported successfully (#{summary}).",
      kind: :info
    ).call
  end

  def create_failure_notification(error)
    ::Notifications::Create.new(
      user: user,
      title: 'Data import failed',
      content: "Your data import failed with error: #{error.message}. Please check the archive format and try again.",
      kind: :error
    ).call
  end

  def validate_import_completeness(expected_counts)
    Rails.logger.info 'Validating import completeness...'

    discrepancies = []

    expected_counts.each do |entity, expected_count|
      actual_count = @import_stats[:"#{entity}_created"] || 0

      if actual_count < expected_count
        discrepancy = "#{entity}: expected #{expected_count}, got #{actual_count} (#{expected_count - actual_count} missing)"
        discrepancies << discrepancy
        Rails.logger.warn "Import discrepancy - #{discrepancy}"
      end
    end

    if discrepancies.any?
      Rails.logger.warn "Import completed with discrepancies: #{discrepancies.join(', ')}"
    else
      Rails.logger.info 'Import validation successful - all entities imported correctly'
    end
  end
end

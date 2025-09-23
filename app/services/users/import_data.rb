# frozen_string_literal: true

require 'zip'

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
    data = stream_and_parse_archive

    import_in_segments(data)

    create_success_notification

    @import_stats
  rescue StandardError => e
    ExceptionReporter.call(e, 'Data import failed')
    create_failure_notification(e)
    raise e
  ensure
    # Clean up any temporary files created during streaming
    cleanup_temporary_files
  end

  private

  attr_reader :user, :archive_path, :import_stats

  def stream_and_parse_archive
    Rails.logger.info "Streaming archive: #{archive_path}"

    @temp_files = {}
    @memory_tracker = Users::ImportData::MemoryTracker.new
    data_json = nil

    @memory_tracker.log('before_zip_processing')

    Zip::File.open(archive_path) do |zip_file|
      zip_file.each do |entry|
        if entry.name == 'data.json'
          Rails.logger.info "Processing data.json (#{entry.size} bytes)"

          # Use streaming JSON parser for all files to reduce memory usage
          streamer = Users::ImportData::JsonStreamer.new(entry)
          data_json = streamer.stream_parse

          @memory_tracker.log('after_json_parsing')
        elsif entry.name.start_with?('files/')
          # Only extract files that are needed for file attachments
          temp_path = stream_file_to_temp(entry)
          @temp_files[entry.name] = temp_path
        end
        # Skip extracting other files to save disk space
      end
    end

    raise StandardError, 'Data file not found in archive: data.json' unless data_json

    @memory_tracker.log('archive_processing_completed')
    data_json
  end

  def stream_file_to_temp(zip_entry)
    require 'tmpdir'

    # Create a temporary file for this attachment
    temp_file = Tempfile.new([File.basename(zip_entry.name, '.*'), File.extname(zip_entry.name)])
    temp_file.binmode

    zip_entry.get_input_stream do |input_stream|
      IO.copy_stream(input_stream, temp_file)
    end

    temp_file.close
    temp_file.path
  end

  def import_in_segments(data)
    Rails.logger.info "Starting segmented data import for user: #{user.email}"

    @memory_tracker&.log('before_core_segment')
    # Segment 1: User settings and core data (small, fast transaction)
    import_core_data_segment(data)

    @memory_tracker&.log('before_independent_segment')
    # Segment 2: Independent entities that can be imported in parallel
    import_independent_entities_segment(data)

    @memory_tracker&.log('before_dependent_segment')
    # Segment 3: Dependent entities that require references
    import_dependent_entities_segment(data)

    # Final validation check
    validate_import_completeness(data['counts']) if data['counts']

    @memory_tracker&.log('import_completed')
    Rails.logger.info "Segmented data import completed. Stats: #{@import_stats}"
  end

  def import_core_data_segment(data)
    ActiveRecord::Base.transaction do
      Rails.logger.info 'Importing core data segment'

      import_settings(data['settings']) if data['settings']
      import_areas(data['areas']) if data['areas']
      import_places(data['places']) if data['places']

      Rails.logger.info 'Core data segment completed'
    end
  end

  def import_independent_entities_segment(data)
    # These entities don't depend on each other and can be imported in parallel
    entity_types = %w[imports exports trips stats notifications].select { |type| data[type] }

    if entity_types.empty?
      Rails.logger.info 'No independent entities to import'
      return
    end

    Rails.logger.info "Processing #{entity_types.size} independent entity types in parallel"

    # Use parallel processing for independent entities
    Parallel.each(entity_types, in_threads: [entity_types.size, 3].min) do |entity_type|
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          case entity_type
          when 'imports'
            import_imports(data['imports'])
          when 'exports'
            import_exports(data['exports'])
          when 'trips'
            import_trips(data['trips'])
          when 'stats'
            import_stats(data['stats'])
          when 'notifications'
            import_notifications(data['notifications'])
          end

          Rails.logger.info "#{entity_type.capitalize} segment completed in parallel"
        end
      end
    end

    Rails.logger.info 'All independent entities processing completed'
  end

  def import_dependent_entities_segment(data)
    ActiveRecord::Base.transaction do
      Rails.logger.info 'Importing dependent entities segment'

      # Import visits after places to ensure proper place resolution
      visits_imported = import_visits(data['visits']) if data['visits']
      Rails.logger.info "Visits import phase completed: #{visits_imported} visits imported"

      # Points are imported in their own optimized batching system
      import_points(data['points']) if data['points']

      Rails.logger.info 'Dependent entities segment completed'
    end
  end

  def import_in_correct_order(data)
    Rails.logger.info "Starting data import for user: #{user.email}"

    Rails.logger.info "Expected entity counts from export: #{data['counts']}" if data['counts']

    Rails.logger.debug "Available data keys: #{data.keys.inspect}"

    import_settings(data['settings']) if data['settings']
    import_areas(data['areas']) if data['areas']

    # Import places first to ensure they're available for visits
    places_imported = import_places(data['places']) if data['places']
    Rails.logger.info "Places import phase completed: #{places_imported} places imported"

    import_imports(data['imports']) if data['imports']
    import_exports(data['exports']) if data['exports']
    import_trips(data['trips']) if data['trips']
    import_stats(data['stats']) if data['stats']
    import_notifications(data['notifications']) if data['notifications']

    # Import visits after places to ensure proper place resolution
    visits_imported = import_visits(data['visits']) if data['visits']
    Rails.logger.info "Visits import phase completed: #{visits_imported} visits imported"

    import_points(data['points']) if data['points']

    # Final validation check
    validate_import_completeness(data['counts']) if data['counts']

    Rails.logger.info "Data import completed. Stats: #{@import_stats}"
  end

  def import_settings(settings_data)
    Rails.logger.debug "Importing settings: #{settings_data.inspect}"
    Users::ImportData::Settings.new(user, settings_data).call
    @import_stats[:settings_updated] = true
  end

  def import_areas(areas_data)
    Rails.logger.debug "Importing #{areas_data&.size || 0} areas"
    areas_created = Users::ImportData::Areas.new(user, areas_data).call
    @import_stats[:areas_created] = areas_created
  end

  def import_places(places_data)
    Rails.logger.debug "Importing #{places_data&.size || 0} places"
    places_created = Users::ImportData::Places.new(user, places_data).call
    @import_stats[:places_created] = places_created
    places_created
  end

  def import_imports(imports_data)
    Rails.logger.debug "Importing #{imports_data&.size || 0} imports"
    imports_created, files_restored = Users::ImportData::Imports.new(user, imports_data, @temp_files).call
    @import_stats[:imports_created] = imports_created
    @import_stats[:files_restored] += files_restored
  end

  def import_exports(exports_data)
    Rails.logger.debug "Importing #{exports_data&.size || 0} exports"
    exports_created, files_restored = Users::ImportData::Exports.new(user, exports_data, @temp_files).call
    @import_stats[:exports_created] = exports_created
    @import_stats[:files_restored] += files_restored
  end

  def import_trips(trips_data)
    Rails.logger.debug "Importing #{trips_data&.size || 0} trips"
    trips_created = Users::ImportData::Trips.new(user, trips_data).call
    @import_stats[:trips_created] = trips_created
  end

  def import_stats(stats_data)
    Rails.logger.debug "Importing #{stats_data&.size || 0} stats"
    stats_created = Users::ImportData::Stats.new(user, stats_data).call
    @import_stats[:stats_created] = stats_created
  end

  def import_notifications(notifications_data)
    Rails.logger.debug "Importing #{notifications_data&.size || 0} notifications"
    notifications_created = Users::ImportData::Notifications.new(user, notifications_data).call
    @import_stats[:notifications_created] = notifications_created
  end

  def import_visits(visits_data)
    Rails.logger.debug "Importing #{visits_data&.size || 0} visits"
    visits_created = Users::ImportData::Visits.new(user, visits_data).call
    @import_stats[:visits_created] = visits_created
    visits_created
  end

  def import_points(points_data)
    Rails.logger.info "About to import #{points_data&.size || 0} points"

    begin
      points_created = Users::ImportData::Points.new(user, points_data).call

      @import_stats[:points_created] = points_created
    rescue StandardError => e
      ExceptionReporter.call(e, 'Points import failed')
      @import_stats[:points_created] = 0
    end
  end

  def cleanup_temporary_files
    return unless @temp_files

    Rails.logger.info "Cleaning up #{@temp_files.size} temporary files"

    @temp_files.each_value do |temp_path|
      File.delete(temp_path) if File.exist?(temp_path)
    rescue StandardError => e
      Rails.logger.warn "Failed to delete temporary file #{temp_path}: #{e.message}"
    end

    @temp_files.clear
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

      next unless actual_count < expected_count

      discrepancy = "#{entity}: expected #{expected_count}, got #{actual_count} (#{expected_count - actual_count} missing)"
      discrepancies << discrepancy
      Rails.logger.warn "Import discrepancy - #{discrepancy}"
    end

    if discrepancies.any?
      Rails.logger.warn "Import completed with discrepancies: #{discrepancies.join(', ')}"
    else
      Rails.logger.info 'Import validation successful - all entities imported correctly'
    end
  end
end

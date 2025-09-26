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
    @import_directory = Rails.root.join('tmp', "import_#{user.email.gsub(/[^0-9A-Za-z._-]/, '_')}_#{Time.current.to_i}")
    FileUtils.mkdir_p(@import_directory)

    ActiveRecord::Base.transaction do
      extract_archive
      data = load_json_data

      import_in_correct_order(data)

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

        extraction_path = File.join(@import_directory, entry.name)
        Rails.logger.debug "Extracting #{entry.name} to #{extraction_path}"

        FileUtils.mkdir_p(File.dirname(extraction_path))

        # Use destination_directory parameter for rubyzip 3.x compatibility
        entry.extract(entry.name, destination_directory: @import_directory)
      end
    end
  end

  def load_json_data
    json_path = @import_directory.join('data.json')

    unless File.exist?(json_path)
      raise StandardError, "Data file not found in archive: data.json"
    end

    JSON.parse(File.read(json_path))
  rescue JSON::ParserError => e
    raise StandardError, "Invalid JSON format in data file: #{e.message}"
  end

  def import_in_correct_order(data)
    Rails.logger.info "Starting data import for user: #{user.email}"

    if data['counts']
      Rails.logger.info "Expected entity counts from export: #{data['counts']}"
    end

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
    if data['counts']
      validate_import_completeness(data['counts'])
    end

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
    imports_created, files_restored = Users::ImportData::Imports.new(user, imports_data, @import_directory.join('files')).call
    @import_stats[:imports_created] = imports_created
    @import_stats[:files_restored] += files_restored
  end

  def import_exports(exports_data)
    Rails.logger.debug "Importing #{exports_data&.size || 0} exports"
    exports_created, files_restored = Users::ImportData::Exports.new(user, exports_data, @import_directory.join('files')).call
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
    Rails.logger.info "Validating import completeness..."

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
      Rails.logger.info "Import validation successful - all entities imported correctly"
    end
  end
end

# frozen_string_literal: true

require 'zip'

# Users::ExportData - Exports complete user data with preserved relationships
#
# Output JSON Structure Example:
# {
#   "counts": {
#     "areas": 5,
#     "imports": 12,
#     "exports": 3,
#     "trips": 8,
#     "stats": 24,
#     "notifications": 10,
#     "points": 15000,
#     "visits": 45,
#     "places": 20
#   },
#   "settings": {
#     "distance_unit": "km",
#     "timezone": "UTC",
#     "immich_url": "https://immich.example.com",
#     // ... other user settings (exported via user.safe_settings.settings)
#   },
#   "areas": [
#     {
#       "name": "Home",
#       "latitude": "40.7128",
#       "longitude": "-74.0060",
#       "radius": 100,
#       "created_at": "2024-01-01T00:00:00Z",
#       "updated_at": "2024-01-01T00:00:00Z"
#     }
#   ],
#   "imports": [
#     {
#       "name": "2023_MARCH.json",
#       "source": "google_semantic_history",
#       "created_at": "2024-01-01T00:00:00Z",
#       "updated_at": "2024-01-01T00:00:00Z",
#       "raw_points": 15432,
#       "doubles": 23,
#       "processed": 15409,
#       "points_count": 15409,
#       "status": "completed",
#       "file_name": "import_1_2023_MARCH.json",
#       "original_filename": "2023_MARCH.json",
#       "file_size": 2048576,
#       "content_type": "application/json"
#       // Note: file_error may be present if file download fails
#       // Note: file_name and original_filename will be null if no file attached
#     }
#   ],
#   "exports": [
#     {
#       "name": "export_2024-01-01_to_2024-01-31.json",
#       "url": null,
#       "status": "completed",
#       "file_format": "json",
#       "file_type": "points",
#       "start_at": "2024-01-01T00:00:00Z",
#       "end_at": "2024-01-31T23:59:59Z",
#       "created_at": "2024-02-01T00:00:00Z",
#       "updated_at": "2024-02-01T00:00:00Z",
#       "file_name": "export_1_export_2024-01-01_to_2024-01-31.json",
#       "original_filename": "export_2024-01-01_to_2024-01-31.json",
#       "file_size": 1048576,
#       "content_type": "application/json"
#       // Note: file_error may be present if file download fails
#       // Note: file_name and original_filename will be null if no file attached
#     }
#   ],
#   "trips": [
#     {
#       "name": "Business Trip to NYC",
#       "started_at": "2024-01-15T08:00:00Z",
#       "ended_at": "2024-01-18T20:00:00Z",
#       "distance": 1245,
#       "path": null, // PostGIS LineString geometry
#       "visited_countries": {"US": "United States", "CA": "Canada"},
#       "created_at": "2024-01-19T00:00:00Z",
#       "updated_at": "2024-01-19T00:00:00Z"
#     }
#   ],
#   "stats": [
#     {
#       "year": 2024,
#       "month": 1,
#       "distance": 456, // Note: integer, not float
#       "daily_distance": {"1": 15.2, "2": 23.5}, // jsonb object
#       "toponyms": [
#         {"country": "United States", "cities": [{"city": "New York"}]}
#       ],
#       "created_at": "2024-02-01T00:00:00Z",
#       "updated_at": "2024-02-01T00:00:00Z"
#     }
#   ],
#   "notifications": [
#     {
#       "kind": "info",
#       "title": "Import completed",
#       "content": "Your data import has been processed successfully",
#       "read_at": "2024-01-01T12:30:00Z", // null if unread
#       "created_at": "2024-01-01T12:00:00Z",
#       "updated_at": "2024-01-01T12:30:00Z"
#     }
#   ],
#   "points": [
#     {
#       "battery_status": "charging",
#       "battery": 85,
#       "timestamp": 1704067200,
#       "altitude": 15.5,
#       "velocity": 25.5,
#       "accuracy": 5.0,
#       "ping": "test-ping",
#       "tracker_id": "tracker-123",
#       "topic": "owntracks/user/device",
#       "trigger": "manual_event",
#       "bssid": "aa:bb:cc:dd:ee:ff",
#       "ssid": "TestWiFi",
#       "connection": "wifi",
#       "vertical_accuracy": 3.0,
#       "mode": 2,
#       "inrids": ["region1", "region2"],
#       "in_regions": ["home", "work"],
#       "raw_data": {"test": "data"},
#       "city": "New York",
#       "country": "United States",
#       "geodata": {"address": "123 Main St"},
#       "reverse_geocoded_at": "2024-01-01T00:00:00Z",
#       "course": 45.5,
#       "course_accuracy": 2.5,
#       "external_track_id": "ext-123",
#       "lonlat": "POINT(-74.006 40.7128)",
#       "longitude": -74.006,
#       "latitude": 40.7128,
#       "created_at": "2024-01-01T00:00:00Z",
#       "updated_at": "2024-01-01T00:00:00Z",
#       "import_reference": {
#         "name": "2023_MARCH.json",
#         "source": "google_semantic_history",
#         "created_at": "2024-01-01T00:00:00Z"
#       },
#       "country_info": {
#         "name": "United States",
#         "iso_a2": "US",
#         "iso_a3": "USA"
#       },
#       "visit_reference": {
#         "name": "Work Visit",
#         "started_at": "2024-01-01T08:00:00Z",
#         "ended_at": "2024-01-01T17:00:00Z"
#       }
#     },
#     {
#       // Example of point without relationships (edge cases)
#       "timestamp": 1704070800,
#       "altitude": 10.0,
#       "longitude": -73.9857,
#       "latitude": 40.7484,
#       "lonlat": "POINT(-73.9857 40.7484)",
#       "created_at": "2024-01-01T00:05:00Z",
#       "updated_at": "2024-01-01T00:05:00Z",
#       "import_reference": null,     // Orphaned point
#       "country_info": null,         // No country data
#       "visit_reference": null       // Not part of a visit
#       // ... other point fields may be null
#     }
#   ],
#   "visits": [
#     {
#       "area_id": 123,
#       "started_at": "2024-01-01T08:00:00Z",
#       "ended_at": "2024-01-01T17:00:00Z",
#       "duration": 32400,
#       "name": "Work Visit",
#       "status": "suggested",
#       "created_at": "2024-01-01T00:00:00Z",
#       "updated_at": "2024-01-01T00:00:00Z",
#       "place_reference": {
#         "name": "Office Building",
#         "latitude": "40.7589",
#         "longitude": "-73.9851",
#         "source": "manual"
#       }
#     },
#     {
#       // Example of visit without place
#       "area_id": null,
#       "started_at": "2024-01-02T10:00:00Z",
#       "ended_at": "2024-01-02T12:00:00Z",
#       "duration": 7200,
#       "name": "Unknown Location",
#       "status": "confirmed",
#       "created_at": "2024-01-02T00:00:00Z",
#       "updated_at": "2024-01-02T00:00:00Z",
#       "place_reference": null       // No associated place
#     }
#   ],
#   "places": [
#     {
#       "name": "Office Building",
#       "longitude": "-73.9851",
#       "latitude": "40.7589",
#       "city": "New York",
#       "country": "United States",
#       "source": "manual",
#       "geodata": {"properties": {"name": "Office Building"}},
#       "reverse_geocoded_at": "2024-01-01T00:00:00Z",
#       "lonlat": "POINT(-73.9851 40.7589)",
#       "created_at": "2024-01-01T00:00:00Z",
#       "updated_at": "2024-01-01T00:00:00Z"
#     }
#   ]
# }
#
# Import Strategy Notes:
# 1. Countries: Look up by name/ISO codes, create if missing
# 2. Imports: Match by name + source + created_at, create new import records
# 3. Places: Match by name + coordinates, create if missing
# 4. Visits: Match by name + timestamps + place_reference, create if missing
# 5. Points: Import with reconstructed foreign keys from references
# 6. Files: Import files are available in the files/ directory with names from file_name fields

class Users::ExportData
  def initialize(user)
    @user = user
  end

  def export
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    @export_directory = Rails.root.join('tmp', "#{user.email.gsub(/[^0-9A-Za-z._-]/, '_')}_#{timestamp}")
    @files_directory = @export_directory.join('files')

    FileUtils.mkdir_p(@files_directory)

    export_record = user.exports.create!(
      name: "user_data_export_#{timestamp}.zip",
      file_format: :archive,
      file_type: :user_data,
      status: :processing
    )

    begin
      json_file_path = @export_directory.join('data.json')

      # Stream JSON writing instead of building in memory
      File.open(json_file_path, 'w') do |file|
        file.write('{"counts":')
        file.write(calculate_entity_counts.to_json)

        file.write(',"settings":')
        file.write(user.safe_settings.settings.to_json)

        file.write(',"areas":')
        file.write(Users::ExportData::Areas.new(user).call.to_json)

        file.write(',"imports":')
        file.write(Users::ExportData::Imports.new(user, @files_directory).call.to_json)

        file.write(',"exports":')
        file.write(Users::ExportData::Exports.new(user, @files_directory).call.to_json)

        file.write(',"trips":')
        file.write(Users::ExportData::Trips.new(user).call.to_json)

        file.write(',"stats":')
        file.write(Users::ExportData::Stats.new(user).call.to_json)

        file.write(',"notifications":')
        file.write(Users::ExportData::Notifications.new(user).call.to_json)

        file.write(',"points":')
        Users::ExportData::Points.new(user, file).call

        file.write(',"visits":')
        file.write(Users::ExportData::Visits.new(user).call.to_json)

        file.write(',"places":')
        file.write(Users::ExportData::Places.new(user).call.to_json)

        file.write('}')
      end

      zip_file_path = @export_directory.join('export.zip')
      create_zip_archive(@export_directory, zip_file_path)

      export_record.file.attach(
        io: File.open(zip_file_path),
        filename: export_record.name,
        content_type: 'application/zip'
      )

      export_record.update!(status: :completed)

      create_success_notification

      export_record
    rescue StandardError => e
      export_record.update!(status: :failed) if export_record

      ExceptionReporter.call(e, 'Export failed')

      raise e
    ensure
      cleanup_temporary_files(@export_directory) if @export_directory&.exist?
    end
  end

  private

  attr_reader :user, :export_directory, :files_directory

  def calculate_entity_counts
    Rails.logger.info 'Calculating entity counts for export'

    counts = {
      areas: user.areas.count,
      imports: user.imports.count,
      exports: user.exports.count,
      trips: user.trips.count,
      stats: user.stats.count,
      notifications: user.notifications.count,
      points: user.points_count.to_i,
      visits: user.visits.count,
      places: user.visited_places.count
    }

    Rails.logger.info "Entity counts: #{counts}"
    counts
  end

  def create_zip_archive(export_directory, zip_file_path)
    original_compression = Zip.default_compression
    Zip.default_compression = Zip::Entry::DEFLATED

    Zip::File.open(zip_file_path, create: true) do |zipfile|
      Dir.glob(export_directory.join('**', '*')).each do |file|
        next if File.directory?(file) || file == zip_file_path.to_s

        relative_path = file.sub(%r{#{export_directory}/}, '')

        zipfile.add(relative_path, file)
      end
    end
  ensure
    Zip.default_compression = original_compression if original_compression
  end

  def cleanup_temporary_files(export_directory)
    return unless File.directory?(export_directory)

    Rails.logger.info "Cleaning up temporary export directory: #{export_directory}"
    FileUtils.rm_rf(export_directory)
  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to cleanup temporary files')
  end

  def create_success_notification
    counts = calculate_entity_counts
    summary = "#{counts[:points]} points, " \
    "#{counts[:visits]} visits, " \
    "#{counts[:places]} places, " \
    "#{counts[:trips]} trips, " \
    "#{counts[:areas]} areas, " \
    "#{counts[:imports]} imports, " \
    "#{counts[:exports]} exports, " \
    "#{counts[:stats]} stats, " \
    "#{counts[:notifications]} notifications"

    ::Notifications::Create.new(
      user: user,
      title: 'Export completed',
      content: "Your data export has been processed successfully (#{summary}). You can download it from the exports page.",
      kind: :info
    ).call
  end
end

# frozen_string_literal: true

require 'zip'

# Users::ExportData - Exports complete user data with preserved relationships
#
# Output JSON Structure Example:
# {
#   "settings": {
#     "distance_unit": "km",
#     "timezone": "UTC",
#     "immich_url": "https://immich.example.com",
#     // ... other user settings
#   },
#   "areas": [
#     {
#       "name": "Home",
#       "latitude": "40.7128",
#       "longitude": "-74.0060",
#       "radius": 100,
#       "created_at": "2024-01-01T00:00:00Z"
#     }
#   ],
#   "imports": [
#     {
#       "name": "2023_MARCH.json",
#       "source": "google_semantic_history",
#       "created_at": "2024-01-01T00:00:00Z",
#       "processed": true,
#       "points_count": 1500,
#       "file_name": "import_1_2023_MARCH.json",
#       "original_filename": "2023_MARCH.json",
#       "file_size": 2048576,
#       "content_type": "application/json"
#     }
#   ],
#   "exports": [
#     {
#       "name": "export_2024-01-01_to_2024-01-31.json",
#       "status": "completed",
#       "file_format": "json",
#       "file_type": "points",
#       "created_at": "2024-02-01T00:00:00Z",
#       "file_name": "export_1_export_2024-01-01_to_2024-01-31.json",
#       "original_filename": "export_2024-01-01_to_2024-01-31.json",
#       "file_size": 1048576,
#       "content_type": "application/json"
#     }
#   ],
#   "trips": [
#     {
#       "name": "Business Trip to NYC",
#       "started_at": "2024-01-15T08:00:00Z",
#       "ended_at": "2024-01-18T20:00:00Z",
#       "distance": 1245.67,
#       "created_at": "2024-01-19T00:00:00Z"
#     }
#   ],
#   "stats": [
#     {
#       "year": 2024,
#       "month": 1,
#       "distance": 456.78,
#       "toponyms": [
#         {"country": "United States", "cities": [{"city": "New York"}]}
#       ],
#       "created_at": "2024-02-01T00:00:00Z"
#     }
#   ],
#   "notifications": [
#     {
#       "kind": "info",
#       "title": "Import completed",
#       "content": "Your data import has been processed successfully",
#       "read": true,
#       "created_at": "2024-01-01T12:00:00Z"
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
#       "created_at": "2024-01-01T00:00:00Z",
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
#       "import_reference": null,     // Orphaned point
#       "country_info": null,         // No country data
#       "visit_reference": null       // Not part of a visit
#     }
#   ],
#   "visits": [
#     {
#       "name": "Work Visit",
#       "started_at": "2024-01-01T08:00:00Z",
#       "ended_at": "2024-01-01T17:00:00Z",
#       "duration": 32400,
#       "status": "suggested",
#       "place_reference": {
#         "name": "Office Building",
#         "latitude": "40.7589",
#         "longitude": "-73.9851",
#         "source": "manual"
#       }
#     },
#     {
#       // Example of visit without place
#       "name": "Unknown Location",
#       "started_at": "2024-01-02T10:00:00Z",
#       "ended_at": "2024-01-02T12:00:00Z",
#       "place_reference": null       // No associated place
#     }
#   ],
#   "places": [
#     {
#       "name": "Office Building",
#       "lonlat": "POINT(-73.9851 40.7589)",
#       "source": "manual",
#       "geodata": {"properties": {"name": "Office Building"}},
#       "created_at": "2024-01-01T00:00:00Z"
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
    @export_directory = export_directory
    @files_directory = files_directory
  end

  def export
    # TODO: Implement
    # 1. Export user settings
    # 2. Export user points
    # 4. Export user visits
    # 8. Export user places

    # 11. Zip all the files

    FileUtils.mkdir_p(files_directory)

    begin
      data = {}

      data[:settings] = user.safe_settings.settings
      data[:areas] = Users::ExportData::Areas.new(user).call
      data[:imports] = Users::ExportData::Imports.new(user, files_directory).call
      data[:exports] = Users::ExportData::Exports.new(user, files_directory).call
      data[:trips] = Users::ExportData::Trips.new(user).call
      data[:stats] = Users::ExportData::Stats.new(user).call
      data[:notifications] = Users::ExportData::Notifications.new(user).call
      data[:points] = Users::ExportData::Points.new(user).call
      data[:visits] = Users::ExportData::Visits.new(user).call
      data[:places] = Users::ExportData::Places.new(user).call

      json_file_path = export_directory.join('data.json')
      File.write(json_file_path, data.to_json)

      zip_file_path = export_directory.join('export.zip')
      create_zip_archive(zip_file_path)

      # Move the zip file to a final location (e.g., tmp root) before cleanup
      final_zip_path = Rails.root.join('tmp', "#{user.email}_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.zip")
      FileUtils.mv(zip_file_path, final_zip_path)

      final_zip_path
    ensure
      cleanup_temporary_files
    end
  end

  private

  attr_reader :user

  def export_directory
    @export_directory ||= Rails.root.join('tmp', "#{user.email}_#{Time.current.strftime('%Y%m%d_%H%M%S')}")
  end

  def files_directory
    @files_directory ||= export_directory.join('files')
  end

  def create_zip_archive(zip_file_path)
    Zip::File.open(zip_file_path, Zip::File::CREATE) do |zipfile|
      Dir.glob(export_directory.join('**', '*')).each do |file|
        next if File.directory?(file) || file == zip_file_path.to_s

        relative_path = file.sub(export_directory.to_s + '/', '')
        zipfile.add(relative_path, file)
      end
    end
  end

  def cleanup_temporary_files
    return unless File.directory?(export_directory)

    Rails.logger.info "Cleaning up temporary export directory: #{export_directory}"
    FileUtils.rm_rf(export_directory)
  rescue StandardError => e
    Rails.logger.error "Failed to cleanup temporary files: #{e.message}"
    # Don't re-raise the error as cleanup failure shouldn't break the export
  end
end

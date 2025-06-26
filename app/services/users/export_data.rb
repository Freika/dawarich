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
        file.write('{"settings":')
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
        file.write(Users::ExportData::Points.new(user).call.to_json)

        file.write(',"visits":')
        file.write(Users::ExportData::Visits.new(user).call.to_json)

        file.write(',"places":')
        file.write(Users::ExportData::Places.new(user).call.to_json)

        file.write('}')
      end

      zip_file_path = @export_directory.join('export.zip')
      create_zip_archive(@export_directory, zip_file_path)

      # Attach the zip file to the Export record
      export_record.file.attach(
        io: File.open(zip_file_path),
        filename: export_record.name,
        content_type: 'application/zip'
      )

      # Mark export as completed
      export_record.update!(status: :completed)

      # Create notification
      create_success_notification

      export_record
    rescue StandardError => e
      # Mark export as failed if an error occurs
      export_record.update!(status: :failed) if export_record
      Rails.logger.error "Export failed: #{e.message}"
      raise e
    ensure
      # Cleanup temporary files
      cleanup_temporary_files(@export_directory) if @export_directory&.exist?
    end
  end

  private

  attr_reader :user

  def export_directory
    @export_directory
  end

  def files_directory
    @files_directory
  end

  def create_zip_archive(export_directory, zip_file_path)
    # Create zip archive with optimized compression
    Zip::File.open(zip_file_path, Zip::File::CREATE) do |zipfile|
      # Set higher compression for better file size reduction
      zipfile.default_compression = Zip::Entry::DEFLATED
      zipfile.default_compression_level = 9  # Maximum compression

      Dir.glob(export_directory.join('**', '*')).each do |file|
        next if File.directory?(file) || file == zip_file_path.to_s

        relative_path = file.sub(export_directory.to_s + '/', '')

        # Add file with specific compression settings
        zipfile.add(relative_path, file) do |entry|
          # JSON files compress very well, so use maximum compression
          if file.end_with?('.json')
            entry.compression_level = 9
          else
            # For other files (images, etc.), use balanced compression
            entry.compression_level = 6
          end
        end
      end
    end
  end

  def cleanup_temporary_files(export_directory)
    return unless File.directory?(export_directory)

    Rails.logger.info "Cleaning up temporary export directory: #{export_directory}"
    FileUtils.rm_rf(export_directory)
  rescue StandardError => e
    Rails.logger.error "Failed to cleanup temporary files: #{e.message}"
    # Don't re-raise the error as cleanup failure shouldn't break the export
  end

  def create_success_notification
    ::Notifications::Create.new(
      user: user,
      title: 'Export completed',
      content: 'Your data export has been processed successfully. You can download it from the exports page.',
      kind: :info
    ).call
  end
end

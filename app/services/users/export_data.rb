# frozen_string_literal: true

require 'zip'

# Users::ExportData - Exports complete user data with preserved relationships
#
# Export Format v2 (JSONL with monthly splitting):
#
# export.zip/
# ├── manifest.json                 # Format version, counts, file listing
# ├── files/                        # Attached files (imports, exports, raw data archives)
# ├── settings.jsonl                # Single line (user settings)
# ├── areas.jsonl                   # One area per line
# ├── tags.jsonl                    # One tag per line
# ├── taggings.jsonl                # One tagging per line (with references)
# ├── imports.jsonl                 # One import record per line
# ├── exports.jsonl                 # One export record per line
# ├── trips.jsonl                   # One trip per line
# ├── notifications.jsonl           # One notification per line
# ├── places.jsonl                  # One place per line
# ├── raw_data_archives.jsonl       # One archive record per line
# ├── points/                       # Points split by year/month
# │   └── YYYY/
# │       └── YYYY-MM.jsonl
# ├── visits/                       # Visits split by started_at year/month
# │   └── YYYY/
# │       └── YYYY-MM.jsonl
# ├── stats/                        # Stats split by their year/month fields
# │   └── YYYY/
# │       └── YYYY-MM.jsonl
# ├── tracks/                       # Tracks split by start_at year/month
# │   └── YYYY/
# │       └── YYYY-MM.jsonl
# └── digests/                      # Digests split by year/month fields
#     └── YYYY/
#         └── YYYY-MM.jsonl
#
# manifest.json structure:
# {
#   "format_version": 2,
#   "dawarich_version": "1.0.0",
#   "exported_at": "2024-01-15T10:30:00Z",
#   "counts": { ... },
#   "files": {
#     "points": ["points/2024/2024-01.jsonl", ...],
#     "visits": ["visits/2024/2024-01.jsonl", ...],
#     "stats": ["stats/2024/2024-01.jsonl", ...]
#   }
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
  FORMAT_VERSION = 2

  def initialize(user)
    @user = user
    @monthly_files = { points: [], visits: [], stats: [], tracks: [], digests: [] }
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
      export_all_data

      write_manifest

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

  attr_reader :user, :export_directory, :files_directory, :monthly_files

  def export_all_data
    Rails.logger.info 'Starting v2 export with JSONL format and monthly splitting'

    # Export simple entities as JSONL files
    export_settings
    export_areas
    export_places
    export_tags
    export_taggings
    export_imports
    export_exports
    export_trips
    export_notifications

    # Export monthly-split entities
    export_points_by_month
    export_visits_by_month
    export_stats_by_month
    export_tracks_by_month
    export_digests_by_month

    # Export entities with files
    export_raw_data_archives
  end

  def export_settings
    settings_path = export_directory.join('settings.jsonl')
    File.open(settings_path, 'w') do |file|
      file.puts(user.safe_settings.settings.to_json)
    end
    Rails.logger.info 'Exported settings'
  end

  def export_areas
    areas_path = export_directory.join('areas.jsonl')
    count = 0
    File.open(areas_path, 'w') do |file|
      user.areas.find_each do |area|
        file.puts(area.as_json(except: %w[user_id id]).to_json)
        count += 1
      end
    end
    Rails.logger.info "Exported #{count} areas"
  end

  def export_places
    places_path = export_directory.join('places.jsonl')
    count = 0
    File.open(places_path, 'w') do |file|
      user.places.find_each do |place|
        file.puts(place.as_json(except: %w[user_id id]).to_json)
        count += 1
      end
    end
    Rails.logger.info "Exported #{count} places"
  end

  def export_imports
    imports_path = export_directory.join('imports.jsonl')
    count = 0
    File.open(imports_path, 'w') do |file|
      Users::ExportData::Imports.new(user, files_directory).call.each do |import_hash|
        file.puts(import_hash.to_json)
        count += 1
      end
    end
    Rails.logger.info "Exported #{count} imports"
  end

  def export_exports
    exports_path = export_directory.join('exports.jsonl')
    count = 0
    File.open(exports_path, 'w') do |file|
      Users::ExportData::Exports.new(user, files_directory).call.each do |export_hash|
        file.puts(export_hash.to_json)
        count += 1
      end
    end
    Rails.logger.info "Exported #{count} exports"
  end

  def export_trips
    trips_path = export_directory.join('trips.jsonl')
    count = 0
    File.open(trips_path, 'w') do |file|
      user.trips.find_each do |trip|
        file.puts(trip.as_json(except: %w[user_id id]).to_json)
        count += 1
      end
    end
    Rails.logger.info "Exported #{count} trips"
  end

  def export_notifications
    notifications_path = export_directory.join('notifications.jsonl')
    count = 0
    File.open(notifications_path, 'w') do |file|
      user.notifications.find_each do |notification|
        file.puts(notification.as_json(except: %w[user_id id]).to_json)
        count += 1
      end
    end
    Rails.logger.info "Exported #{count} notifications"
  end

  def export_tags
    tags_path = export_directory.join('tags.jsonl')
    count = 0
    File.open(tags_path, 'w') do |file|
      user.tags.find_each do |tag|
        file.puts(tag.as_json(except: %w[user_id id]).to_json)
        count += 1
      end
    end
    Rails.logger.info "Exported #{count} tags"
  end

  def export_taggings
    taggings_path = export_directory.join('taggings.jsonl')
    count = 0
    File.open(taggings_path, 'w') do |file|
      user.tags.includes(taggings: :taggable).find_each do |tag|
        tag.taggings.each do |tagging|
          tagging_hash = build_tagging_hash(tag, tagging)
          file.puts(tagging_hash.to_json)
          count += 1
        end
      end
    end
    Rails.logger.info "Exported #{count} taggings"
  end

  def build_tagging_hash(tag, tagging)
    hash = {
      'tag_name' => tag.name,
      'taggable_type' => tagging.taggable_type,
      'created_at' => tagging.created_at,
      'updated_at' => tagging.updated_at
    }

    if tagging.taggable.present?
      hash['taggable_name'] = tagging.taggable.try(:name)
      hash['taggable_latitude'] = tagging.taggable.try(:latitude)&.to_s
      hash['taggable_longitude'] = tagging.taggable.try(:longitude)&.to_s
    end

    hash
  end

  def export_points_by_month
    points_dir = export_directory.join('points')
    FileUtils.mkdir_p(points_dir)

    exporter = Users::ExportData::Points.new(user, points_dir)
    @monthly_files[:points] = exporter.call
    Rails.logger.info "Exported points to #{@monthly_files[:points].size} monthly files"
  end

  def export_visits_by_month
    visits_dir = export_directory.join('visits')
    FileUtils.mkdir_p(visits_dir)

    exporter = Users::ExportData::Visits.new(user, visits_dir)
    @monthly_files[:visits] = exporter.call
    Rails.logger.info "Exported visits to #{@monthly_files[:visits].size} monthly files"
  end

  def export_stats_by_month
    stats_dir = export_directory.join('stats')
    FileUtils.mkdir_p(stats_dir)

    exporter = Users::ExportData::Stats.new(user, stats_dir)
    @monthly_files[:stats] = exporter.call
    Rails.logger.info "Exported stats to #{@monthly_files[:stats].size} monthly files"
  end

  def export_tracks_by_month
    tracks_dir = export_directory.join('tracks')
    FileUtils.mkdir_p(tracks_dir)

    exporter = Users::ExportData::Tracks.new(user, tracks_dir)
    @monthly_files[:tracks] = exporter.call
    Rails.logger.info "Exported tracks to #{@monthly_files[:tracks].size} monthly files"
  end

  def export_digests_by_month
    digests_dir = export_directory.join('digests')
    FileUtils.mkdir_p(digests_dir)

    exporter = Users::ExportData::Digests.new(user, digests_dir)
    @monthly_files[:digests] = exporter.call
    Rails.logger.info "Exported digests to #{@monthly_files[:digests].size} monthly files"
  end

  def export_raw_data_archives
    archives_path = export_directory.join('raw_data_archives.jsonl')
    count = 0
    File.open(archives_path, 'w') do |file|
      user.raw_data_archives.find_each do |archive|
        archive_hash = archive.as_json(except: %w[user_id id])

        if archive.file.attached?
          file_name = "raw_data_archive_#{archive.year}_#{format('%02d', archive.month)}_#{archive.chunk_number}.gz"
          archive_hash['file_name'] = file_name
          archive_hash['original_filename'] = archive.file.filename.to_s
          archive_hash['content_type'] = archive.file.content_type

          dest_path = files_directory.join(file_name)
          File.open(dest_path, 'wb') { |f| archive.file.download { |chunk| f.write(chunk) } }
        end

        file.puts(archive_hash.to_json)
        count += 1
      end
    end
    Rails.logger.info "Exported #{count} raw data archives"
  end

  def write_manifest
    manifest = {
      format_version: FORMAT_VERSION,
      dawarich_version: dawarich_version,
      exported_at: Time.current.utc.iso8601,
      counts: calculate_entity_counts,
      files: {
        points: monthly_files[:points],
        visits: monthly_files[:visits],
        stats: monthly_files[:stats],
        tracks: monthly_files[:tracks],
        digests: monthly_files[:digests]
      }
    }

    manifest_path = export_directory.join('manifest.json')
    File.write(manifest_path, JSON.pretty_generate(manifest))
    Rails.logger.info "Wrote manifest.json with format_version #{FORMAT_VERSION}"
  end

  def dawarich_version
    defined?(APP_VERSION) ? APP_VERSION : 'unknown'
  end

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
      places: user.visited_places.count,
      tags: user.tags.count,
      tracks: user.tracks.count,
      digests: user.digests.count,
      raw_data_archives: user.raw_data_archives.count
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
      "#{counts[:tags]} tags, " \
      "#{counts[:tracks]} tracks, " \
      "#{counts[:digests]} digests, " \
      "#{counts[:notifications]} notifications"

    ::Notifications::Create.new(
      user: user,
      title: 'Export completed',
      content: "Your data export has been processed successfully (#{summary}). " \
               'You can download it from the exports page.',
      kind: :info
    ).call
  end
end

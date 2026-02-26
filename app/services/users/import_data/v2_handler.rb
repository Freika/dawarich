# frozen_string_literal: true

require 'oj'

# Users::ImportData::V2Handler - Handles import of v2 format archives
#
# V2 format structure:
# export.zip/
# ├── manifest.json              # Format version, counts, file listing
# ├── files/                     # Attached files (imports, exports, raw data archives)
# ├── settings.jsonl             # Single line
# ├── areas.jsonl                # One area per line
# ├── tags.jsonl                 # One tag per line
# ├── taggings.jsonl             # One tagging per line
# ├── imports.jsonl              # One import record per line
# ├── exports.jsonl              # One export record per line
# ├── trips.jsonl                # One trip per line
# ├── notifications.jsonl        # One notification per line
# ├── places.jsonl               # One place per line
# ├── raw_data_archives.jsonl    # One archive record per line
# ├── points/                    # Points split by year/month
# │   └── YYYY/
# │       └── YYYY-MM.jsonl
# ├── visits/                    # Visits split by started_at year/month
# │   └── YYYY/
# │       └── YYYY-MM.jsonl
# ├── stats/                     # Stats split by their year/month fields
# │   └── YYYY/
# │       └── YYYY-MM.jsonl
# ├── tracks/                    # Tracks split by start_at year/month
# │   └── YYYY/
# │       └── YYYY-MM.jsonl
# └── digests/                   # Digests split by year/month fields
#     └── YYYY/
#         └── YYYY-MM.jsonl

class Users::ImportData::V2Handler
  BATCH_SIZE = 5000

  def initialize(user, import_directory, import_stats)
    @user = user
    @import_directory = import_directory
    @import_stats = import_stats
    @manifest = nil
  end

  def process
    Rails.logger.info "Processing v2 format archive for user: #{user.email}"

    load_manifest

    # Import in dependency order
    import_settings
    import_areas
    import_places
    import_tags
    import_taggings
    import_imports
    import_exports
    import_trips
    import_stats_from_files
    import_digests_from_files
    import_notifications
    import_visits_from_files
    import_tracks_from_files
    import_points_from_files
    import_raw_data_archives

    Rails.logger.info "V2 data import completed. Stats: #{import_stats}"
  end

  def expected_counts
    @manifest&.dig('counts')
  end

  private

  attr_reader :user, :import_directory, :import_stats

  def load_manifest
    manifest_path = import_directory.join('manifest.json')
    raise StandardError, 'Manifest file not found in archive: manifest.json' unless File.exist?(manifest_path)

    @manifest = JSON.parse(File.read(manifest_path))
    Rails.logger.info "Loaded manifest: format_version=#{@manifest['format_version']}, " \
                      "dawarich_version=#{@manifest['dawarich_version']}, " \
                      "exported_at=#{@manifest['exported_at']}"
  end

  def import_settings
    settings_path = import_directory.join('settings.jsonl')
    return unless File.exist?(settings_path)

    File.foreach(settings_path) do |line|
      line = line.strip
      next if line.blank?

      settings_data = Oj.load(line)
      Users::ImportData::Settings.new(user, settings_data).call
      import_stats[:settings_updated] = true
      break # Only one line expected
    end

    Rails.logger.debug 'Imported settings'
  end

  def import_areas
    import_jsonl_file('areas.jsonl') do |areas_data|
      areas_created = Users::ImportData::Areas.new(user, areas_data).call.to_i
      import_stats[:areas_created] += areas_created
    end
  end

  def import_places
    places_path = import_directory.join('places.jsonl')
    return unless File.exist?(places_path)

    batch = []
    File.foreach(places_path) do |line|
      line = line.strip
      next if line.blank?

      batch << Oj.load(line)
      if batch.size >= BATCH_SIZE
        places_created = Users::ImportData::Places.new(user, batch).call.to_i
        import_stats[:places_created] += places_created
        batch = []
      end
    end

    if batch.any?
      places_created = Users::ImportData::Places.new(user, batch).call.to_i
      import_stats[:places_created] += places_created
    end

    Rails.logger.debug "Imported places: #{import_stats[:places_created]}"
  end

  def import_tags
    import_jsonl_file('tags.jsonl') do |tags_data|
      tags_created = Users::ImportData::Tags.new(user, tags_data).call.to_i
      import_stats[:tags_created] += tags_created
    end
  end

  def import_taggings
    import_jsonl_file('taggings.jsonl') do |taggings_data|
      taggings_created = Users::ImportData::Taggings.new(user, taggings_data).call.to_i
      import_stats[:taggings_created] += taggings_created
    end
  end

  def import_imports
    import_jsonl_file('imports.jsonl') do |imports_data|
      imports_created, files_restored = Users::ImportData::Imports.new(
        user, imports_data, import_directory.join('files')
      ).call
      import_stats[:imports_created] += imports_created.to_i
      import_stats[:files_restored] += files_restored.to_i
    end
  end

  def import_exports
    import_jsonl_file('exports.jsonl') do |exports_data|
      exports_created, files_restored = Users::ImportData::Exports.new(
        user, exports_data, import_directory.join('files')
      ).call
      import_stats[:exports_created] += exports_created.to_i
      import_stats[:files_restored] += files_restored.to_i
    end
  end

  def import_trips
    import_jsonl_file('trips.jsonl') do |trips_data|
      trips_created = Users::ImportData::Trips.new(user, trips_data).call.to_i
      import_stats[:trips_created] += trips_created
    end
  end

  def import_notifications
    import_jsonl_file('notifications.jsonl') do |notifications_data|
      notifications_created = Users::ImportData::Notifications.new(user, notifications_data).call.to_i
      import_stats[:notifications_created] += notifications_created
    end
  end

  def import_stats_from_files
    stats_files = @manifest.dig('files', 'stats') || []

    if stats_files.empty?
      # Fallback: check for stats.jsonl in root (shouldn't happen in v2, but be safe)
      import_jsonl_file('stats.jsonl') do |stats_data|
        stats_created = Users::ImportData::Stats.new(user, stats_data).call.to_i
        import_stats[:stats_created] += stats_created
      end
      return
    end

    # Process monthly stats files in sorted order
    stats_files.sort.each do |relative_path|
      file_path = import_directory.join(relative_path)
      next unless File.exist?(file_path)

      batch = read_jsonl_file(file_path)
      next if batch.empty?

      stats_created = Users::ImportData::Stats.new(user, batch).call.to_i
      import_stats[:stats_created] += stats_created
      Rails.logger.debug "Imported #{stats_created} stats from #{relative_path}"
    end
  end

  def import_digests_from_files
    digests_files = @manifest.dig('files', 'digests') || []

    if digests_files.empty?
      import_jsonl_file('digests.jsonl') do |digests_data|
        digests_created = Users::ImportData::Digests.new(user, digests_data).call.to_i
        import_stats[:digests_created] += digests_created
      end
      return
    end

    digests_files.sort.each do |relative_path|
      file_path = import_directory.join(relative_path)
      next unless File.exist?(file_path)

      batch = read_jsonl_file(file_path)
      next if batch.empty?

      digests_created = Users::ImportData::Digests.new(user, batch).call.to_i
      import_stats[:digests_created] += digests_created
      Rails.logger.debug "Imported #{digests_created} digests from #{relative_path}"
    end
  end

  def import_tracks_from_files
    tracks_files = @manifest.dig('files', 'tracks') || []

    if tracks_files.empty?
      import_jsonl_file('tracks.jsonl') do |tracks_data|
        tracks_created = Users::ImportData::Tracks.new(user, tracks_data).call.to_i
        import_stats[:tracks_created] += tracks_created
      end
      return
    end

    tracks_files.sort.each do |relative_path|
      file_path = import_directory.join(relative_path)
      next unless File.exist?(file_path)

      batch = read_jsonl_file(file_path)
      next if batch.empty?

      tracks_created = Users::ImportData::Tracks.new(user, batch).call.to_i
      import_stats[:tracks_created] += tracks_created
      Rails.logger.debug "Imported #{tracks_created} tracks from #{relative_path}"
    end
  end

  def import_raw_data_archives
    import_jsonl_file('raw_data_archives.jsonl') do |archives_data|
      archives_created, files_restored = Users::ImportData::RawDataArchives.new(
        user, archives_data, import_directory.join('files')
      ).call
      import_stats[:raw_data_archives_created] += archives_created.to_i
      import_stats[:files_restored] += files_restored.to_i
    end
  end

  def import_visits_from_files
    visits_files = @manifest.dig('files', 'visits') || []

    if visits_files.empty?
      # Fallback: check for visits.jsonl in root
      import_jsonl_file('visits.jsonl') do |visits_data|
        visits_data.each_slice(BATCH_SIZE) do |batch|
          import_visits_batch(batch)
        end
      end
      return
    end

    # Process monthly visits files in sorted order
    visits_files.sort.each do |relative_path|
      import_visits_from_monthly_file(relative_path)
    end
  end

  def import_visits_from_monthly_file(relative_path)
    file_path = import_directory.join(relative_path)
    return unless File.exist?(file_path)

    batch = []
    File.foreach(file_path) do |line|
      line = line.strip
      next if line.blank?

      batch << Oj.load(line)
      if batch.size >= BATCH_SIZE
        import_visits_batch(batch)
        batch = []
      end
    end

    import_visits_batch(batch) if batch.any?
    Rails.logger.debug "Imported visits from #{relative_path}"
  end

  def import_visits_batch(batch)
    visits_created = Users::ImportData::Visits.new(user, batch).call.to_i
    import_stats[:visits_created] += visits_created
  end

  def import_points_from_files
    points_files = @manifest.dig('files', 'points') || []

    if points_files.empty?
      # Fallback: check for points.jsonl in root
      points_path = import_directory.join('points.jsonl')
      if File.exist?(points_path)
        importer = Users::ImportData::Points.new(user, nil, batch_size: BATCH_SIZE)
        File.foreach(points_path) do |line|
          line = line.strip
          next if line.blank?

          importer.add(Oj.load(line))
        end
        import_stats[:points_created] = importer.finalize.to_i
      end
      return
    end

    # Process monthly points files in sorted order
    importer = Users::ImportData::Points.new(user, nil, batch_size: BATCH_SIZE)

    points_files.sort.each do |relative_path|
      file_path = import_directory.join(relative_path)
      next unless File.exist?(file_path)

      File.foreach(file_path) do |line|
        line = line.strip
        next if line.blank?

        importer.add(Oj.load(line))
      end

      Rails.logger.debug "Processed points from #{relative_path}"
    end

    import_stats[:points_created] = importer.finalize.to_i
  end

  # Helper to read a JSONL file and collect all records
  def import_jsonl_file(filename)
    file_path = import_directory.join(filename)
    return unless File.exist?(file_path)

    data = read_jsonl_file(file_path)
    yield(data) if data.any?
  end

  def read_jsonl_file(file_path)
    data = []
    File.foreach(file_path) do |line|
      line = line.strip
      next if line.blank?

      data << Oj.load(line)
    end
    data
  end
end

# frozen_string_literal: true

require 'zip'
require 'oj'

# Users::ImportData - Imports complete user data from exported archive
#
# This service processes a ZIP archive created by Users::ExportData and recreates
# the user's data with preserved relationships. It supports both v1 (legacy) and
# v2 (JSONL with monthly splitting) formats.
#
# Format Detection:
# - If manifest.json exists -> v2 format (JSONL with monthly files)
# - If data.json exists -> v1 format (legacy single JSON file)
#
# The import follows a specific order to handle foreign key dependencies:
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
  STREAM_BATCH_SIZE = 5000
  STREAMED_SECTIONS = %w[places visits points].freeze
  MAX_ENTRY_SIZE = 10.gigabytes # Maximum size for a single file in the archive

  def initialize(user, archive_path)
    @user = user
    @archive_path = archive_path
    @import_stats = {
      settings_updated: false,
      areas_created: 0,
      places_created: 0,
      tags_created: 0,
      taggings_created: 0,
      imports_created: 0,
      exports_created: 0,
      trips_created: 0,
      stats_created: 0,
      digests_created: 0,
      notifications_created: 0,
      visits_created: 0,
      tracks_created: 0,
      points_created: 0,
      raw_data_archives_created: 0,
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

        # Validate entry size before extraction
        if entry.size > MAX_ENTRY_SIZE
          Rails.logger.error "Skipping oversized entry: #{entry.name} (#{entry.size} bytes exceeds #{MAX_ENTRY_SIZE} bytes)"
          raise "Archive entry #{entry.name} exceeds maximum allowed size"
        end

        FileUtils.mkdir_p(File.dirname(extraction_path))

        # Manual extraction to bypass size validation for large files
        entry.get_input_stream do |input|
          File.open(extraction_path, 'wb') do |output|
            IO.copy_stream(input, output)
          end
        end
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

    format_version = detect_format_version
    Rails.logger.info "Detected archive format version: #{format_version}"

    handler = create_handler(format_version)
    handler.process

    expected_counts = handler.expected_counts
    validate_import_completeness(expected_counts) if expected_counts.present?
  end

  def detect_format_version
    manifest_path = @import_directory.join('manifest.json')
    data_json_path = @import_directory.join('data.json')

    if File.exist?(manifest_path)
      begin
        manifest = JSON.parse(File.read(manifest_path))
        manifest['format_version'] || 2
      rescue JSON::ParserError
        Rails.logger.warn 'Failed to parse manifest.json, falling back to v2'
        2
      end
    elsif File.exist?(data_json_path)
      1 # Legacy format
    else
      raise StandardError, 'Unknown export format: neither manifest.json nor data.json found'
    end
  end

  def create_handler(format_version)
    case format_version
    when 1
      Users::ImportData::V1Handler.new(user, @import_directory, @import_stats)
    when 2
      Users::ImportData::V2Handler.new(user, @import_directory, @import_stats)
    else
      raise StandardError, "Unsupported export format version: #{format_version}"
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
      "#{@import_stats[:tags_created]} tags, " \
      "#{@import_stats[:tracks_created]} tracks, " \
      "#{@import_stats[:digests_created]} digests, " \
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

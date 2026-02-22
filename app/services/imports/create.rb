# frozen_string_literal: true

class Imports::Create
  include Imports::Broadcaster

  attr_reader :user, :import

  def initialize(user, import)
    @user = user
    @import = import
  end

  def call
    import.update!(status: :processing)
    broadcast_status_update

    temp_file_path = Imports::SecureFileDownloader.new(import.file).download_to_temp_file

    source = if import.source.nil? || should_detect_source?
               detect_source_from_file(temp_file_path)
             else
               import.source
             end

    import.update!(source: source)
    importer(source).new(import, user.id, temp_file_path).call

    schedule_stats_creating(user.id)
    schedule_visit_suggesting(user.id, import)
    update_import_points_count(import)
    User.reset_counters(user.id, :points)
  rescue StandardError => e
    import.update!(status: :failed, error_message: e.message)
    broadcast_status_update

    ExceptionReporter.call(e, 'Import failed')

    create_import_failed_notification(import, user, e)
  ensure
    if temp_file_path && File.exist?(temp_file_path)
      File.unlink(temp_file_path)
    end

    if import.processing?
      import.update!(status: :completed)
      broadcast_status_update
    end
  end

  private

  def importer(source)
    raise ArgumentError, 'Import source cannot be nil' if source.nil?

    case source.to_s
    when 'google_semantic_history'      then GoogleMaps::SemanticHistoryImporter
    when 'google_phone_takeout'         then GoogleMaps::PhoneTakeoutImporter
    when 'google_records'               then GoogleMaps::RecordsStorageImporter
    when 'owntracks'                    then OwnTracks::Importer
    when 'gpx'                          then Gpx::TrackImporter
    when 'kml'                          then Kml::Importer
    when 'geojson'                      then Geojson::Importer
    when 'immich_api', 'photoprism_api' then Photos::Importer
    else
      raise ArgumentError, "Unsupported source: #{source}"
    end
  end

  def update_import_points_count(import)
    Import::UpdatePointsCountJob.perform_later(import.id)
  end

  def schedule_stats_creating(user_id)
    import.years_and_months_tracked.each do |year, month|
      Stats::CalculatingJob.perform_later(user_id, year, month)
    end
  end

  def schedule_visit_suggesting(user_id, import)
    return unless user.safe_settings.visits_suggestions_enabled?

    min_max = import.points.pluck('MIN(timestamp), MAX(timestamp)').first
    return if min_max.compact.empty?

    start_at = Time.zone.at(min_max[0])
    end_at = Time.zone.at(min_max[1])

    VisitSuggestingJob.perform_later(user_id:, start_at:, end_at:)
  end

  def create_import_failed_notification(import, user, error)
    message = import_failed_message(import, error)

    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Import failed',
      content: message
    ).call
  end

  def should_detect_source?
    # Don't override API-based sources that can't be reliably detected
    !%w[immich_api photoprism_api].include?(import.source)
  end

  def detect_source_from_file(temp_file_path)
    detector = Imports::SourceDetector.new_from_file_header(temp_file_path)

    detector.detect_source!
  end

  def import_failed_message(import, error)
    if DawarichSettings.self_hosted?
      "Import \"#{import.name}\" failed: #{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    else
      "Import \"#{import.name}\" failed, please contact us at hi@dawarich.com"
    end
  end
end

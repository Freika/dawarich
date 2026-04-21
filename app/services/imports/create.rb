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
    inner_file_path = nil

    dispatch = Archive::Unzipper.inspect_archive(temp_file_path)

    case dispatch.kind
    when :multi_entry
      Imports::ZipExtractor.new(import, user.id, temp_file_path).call
      return
    when :single_entry
      inner_file_path = Archive::Unzipper.extract_single(temp_file_path)
      run_importer(inner_file_path)
    else
      run_importer(temp_file_path)
    end

    User.where(id: user.id).update_all(points_count: user.points.count)

    filter_anomalies(user, import)
    schedule_stats_creating(user.id)
    schedule_visit_suggesting(user.id, import)
    update_import_points_count(import)
  rescue StandardError => e
    return if import.destroyed?

    import.update!(status: :failed, error_message: e.message)
    broadcast_status_update

    ExceptionReporter.call(e, 'Import failed')

    create_import_failed_notification(import, user, e)
  ensure
    File.unlink(temp_file_path) if temp_file_path && File.exist?(temp_file_path)
    File.unlink(inner_file_path) if inner_file_path && File.exist?(inner_file_path)

    if !import.destroyed? && import.processing?
      import.update!(status: :completed)
      broadcast_status_update
    end
  end

  private

  def run_importer(path)
    source = import.source.presence || detect_source_from_file(path)
    import.update!(source: source) if import.source != source.to_s
    importer(source).new(import, user.id, path).call
  end

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
    when 'csv'                          then Csv::Importer
    when 'tcx'                          then Tcx::Importer
    when 'fit'                          then Fit::Importer
    else
      raise ArgumentError, "Unsupported source: #{source}"
    end
  end

  def update_import_points_count(import)
    Import::UpdatePointsCountJob.perform_later(import.id)
  end

  def filter_anomalies(user, import)
    min_ts = import.points.minimum(:timestamp)
    max_ts = import.points.maximum(:timestamp)
    return unless min_ts && max_ts

    Points::AnomalyFilter.new(user.id, min_ts, max_ts).call
  end

  def schedule_stats_creating(user_id)
    import.years_and_months_tracked.each do |year, month|
      Stats::CalculatingJob.perform_later(user_id, year, month)
    end
  end

  def schedule_visit_suggesting(user_id, import)
    return unless user.safe_settings.visits_suggestions_enabled?

    min_max = import.points.pick('MIN(timestamp), MAX(timestamp)')
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

  def detect_source_from_file(file_path)
    detector = Imports::SourceDetector.new_from_file_header(file_path)

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

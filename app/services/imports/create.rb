# frozen_string_literal: true

class Imports::Create
  include Imports::Broadcaster

  attr_reader :user, :import

  def initialize(user, import)
    @user = user
    @import = import
  end

  def call
    import.update!(status: :processing, raw_points: 0, doubles: 0)
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

    post_import_processing
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

  def post_import_processing
    run_post_import_step('points_count') { User.where(id: user.id).update_all(points_count: user.points.count) }
    run_post_import_step('filter_anomalies') { filter_anomalies(user, import) }
    run_post_import_step('schedule_stats') { schedule_stats_creating(user.id) }
    run_post_import_step('schedule_visit_suggesting') { schedule_visit_suggesting(user.id, import) }
    run_post_import_step('schedule_track_generation') { schedule_track_generation(user.id, import) }
    run_post_import_step('update_points_count') { update_import_points_count(import) }
    run_post_import_step('notify_if_all_skipped') { notify_if_all_skipped(import) }
  end

  def run_post_import_step(step)
    yield
  rescue StandardError => e
    ExceptionReporter.call(e, "Post-import processing failed: #{step}")
    create_post_import_failure_notification(step)
  end

  def create_post_import_failure_notification(step)
    return if @post_import_failure_notified

    @post_import_failure_notified = true

    Notifications::Create.new(
      user:,
      kind: :warning,
      title: 'Import post-processing incomplete',
      content: "Your import \"#{import.name}\" finished and all points were saved, but the " \
               "#{step.tr('_', ' ')} step failed. Statistics, tracks or visit suggestions " \
               'may be missing or outdated. You can trigger a recalculation from Settings.'
    ).call
  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to create post-import failure notification')
  end

  def run_importer(path)
    source = import.source.presence || detect_source_from_file(path)
    import.update!(source: source) if import.source.to_s != source.to_s
    importer(source).new(import, user.id, path).call
  end

  def importer(source)
    raise ArgumentError, 'Import source cannot be nil' if source.nil?

    case source.to_s
    when 'google_semantic_history'      then GoogleMaps::SemanticHistoryImporter
    when 'google_phone_takeout'         then GoogleMaps::PhoneTakeoutImporter
    when 'google_records'               then GoogleMaps::RecordsStorageImporter
    when 'google_photos'                then GooglePhotos::Importer
    when 'owntracks'                    then OwnTracks::Importer
    when 'gpx'                          then Gpx::TrackImporter
    when 'kml'                          then Kml::Importer
    when 'geojson'                      then Geojson::Importer
    when 'immich_api', 'photoprism_api' then Photos::Importer
    when 'csv'                          then Csv::Importer
    when 'tcx'                          then Tcx::Importer
    when 'fit'                          then Fit::Importer
    when 'polarsteps'                   then Polarsteps::Importer
    when 'zip'
      raise ArgumentError, 'Could not classify zip contents -- file may be corrupted'
    else
      raise ArgumentError, "Unsupported source: #{source}"
    end
  end

  def update_import_points_count(import)
    Import::UpdatePointsCountJob.perform_later(import.id)
  end

  def notify_if_all_skipped(import)
    import.reload
    return unless import.doubles.to_i.positive? && import.points.count.zero?

    Notification.create!(
      user_id: import.user_id,
      title: 'Import completed with no new points',
      content: "Your file #{import.name} contained #{import.raw_points} points, all of which " \
               'already exist in your timeline at the same coordinates and timestamps. ' \
               'Nothing was imported. If this was unexpected, delete the existing points ' \
               'for that date range and re-import.',
      kind: :info
    )
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

    summary = import_points_summary(import)
    return if summary.nil?

    VisitSuggestingJob.perform_later(user_id:, start_at: summary[:start_at], end_at: summary[:end_at])
  end

  def schedule_track_generation(user_id, import)
    summary = import_points_summary(import)
    return if summary.nil? || summary[:count] < 2

    Tracks::ParallelGeneratorJob.perform_later(
      user_id,
      start_at: summary[:start_at],
      end_at: summary[:end_at],
      mode: :bulk,
      untracked_only: true
    )
  end

  def import_points_summary(import)
    return @import_points_summary if defined?(@import_points_summary)

    count, min_ts, max_ts = import.points.pick(Arel.sql('COUNT(*), MIN(timestamp), MAX(timestamp)'))

    @import_points_summary =
      if min_ts.nil? || max_ts.nil?
        nil
      else
        { count: count, start_at: Time.zone.at(min_ts), end_at: Time.zone.at(max_ts) }
      end
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

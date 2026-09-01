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

    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user:,
        kind: :warning,
        title: I18n.t('services.imports.create.import_post_processing_incomplete'),
        content: I18n.t('services.imports.create.your_import_name_finished_and_all_points_were_saved_but',
                        name: import.name, step: step.tr('_', ' '))
      ).call
    end
  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to create post-import failure notification')
  end

  def run_importer(path)
    source = import.source.presence || detect_source_from_file(path)
    import.update!(source: source) if import.source.to_s != source.to_s
    importer(source).new(import, user.id, path).call
  end

  def importer(source)
    raise ArgumentError, I18n.t('services.imports.create.source_missing') if source.nil?

    case source.to_s
    when 'google_semantic_history'      then GoogleMaps::SemanticHistoryImporter
    when 'google_phone_takeout'         then GoogleMaps::PhoneTakeoutImporter
    when 'google_records'               then GoogleMaps::RecordsStorageImporter
    when 'google_photos'                then GooglePhotos::Importer
    when 'mobile_photo_library'         then MobilePhotoLibrary::Importer
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
      raise ArgumentError, I18n.t('services.imports.create.zip_unclassified')
    else
      raise ArgumentError, I18n.t('services.imports.create.unsupported_source', source:)
    end
  end

  def update_import_points_count(import)
    Import::UpdatePointsCountJob.perform_later(import.id)
  end

  def notify_if_all_skipped(import)
    import.reload
    return unless import.points.count.zero?
    return if awaiting_place_extraction?(import)

    if import.doubles.to_i.positive?
      I18n.with_locale(import.user.locale) do
        Notification.create!(
          user_id: import.user_id,
          title: I18n.t('services.imports.create.import_completed_with_no_new_points'),
          content: I18n.t('services.imports.create.your_file_name_contained_raw_points_points_all_of_which',
                          name: import.name, raw_points: import.raw_points),
          kind: :info
        )
      end
    else
      I18n.with_locale(import.user.locale) do
        Notification.create!(
          user_id: import.user_id,
          title: I18n.t('services.imports.create.import_completed_with_no_points'),
          content: zero_points_content(import),
          kind: :warning
        )
      end
    end
  end

  def awaiting_place_extraction?(import)
    return false unless import.additional_data_extraction_supported?

    data = import.raw_data || {}
    return false if data['trackpoints_seen'].to_i.positive?
    return false unless data['waypoints_seen'].to_i.positive?

    !import.additional_data_extraction_completed?
  end

  def zero_points_content(import)
    if import.gpx? || import.kml? || import.geojson?
      I18n.t('services.imports.create.zero_points_with_timestamps', name: import.name)
    else
      I18n.t('services.imports.create.zero_points', name: import.name)
    end
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
    # The message is built inside the block: translating it a line earlier left
    # the notification with a title in the reader's language and a body in
    # whatever language the request happened to run in.
    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user:,
        kind: :error,
        title: I18n.t('services.imports.create.import_failed'),
        content: import_failed_message(import, error)
      ).call
    end
  end

  def detect_source_from_file(file_path)
    detector = Imports::SourceDetector.new_from_file_header(file_path)

    detector.detect_source!
  end

  def import_failed_message(import, error)
    if DawarichSettings.self_hosted?
      I18n.t(
        'services.imports.create.import_failed_self_hosted',
        name: import.name,
        message: error.message,
        backtrace: error.backtrace.join("\n")
      )
    else
      I18n.t('services.imports.create.import_failed_cloud', name: import.name)
    end
  end
end

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

    importer(import.source).new(import, user.id).call

    schedule_stats_creating(user.id)
    schedule_visit_suggesting(user.id, import)
    update_import_points_count(import)
  rescue StandardError => e
    import.update!(status: :failed)
    broadcast_status_update

    create_import_failed_notification(import, user, e)
  ensure
    if import.processing?
      import.update!(status: :completed)
      broadcast_status_update
    end
  end

  private

  def importer(source)
    case source
    when 'google_semantic_history'      then GoogleMaps::SemanticHistoryImporter
    when 'google_phone_takeout'         then GoogleMaps::PhoneTakeoutImporter
    when 'google_records'               then GoogleMaps::RecordsStorageImporter
    when 'owntracks'                    then OwnTracks::Importer
    when 'gpx'                          then Gpx::TrackImporter
    when 'geojson'                      then Geojson::Importer
    when 'immich_api', 'photoprism_api' then Photos::Importer
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

    points = import.points.order(:timestamp)

    return if points.none?

    start_at = Time.zone.at(points.first.timestamp)
    end_at = Time.zone.at(points.last.timestamp)

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

  def import_failed_message(import, error)
    if DawarichSettings.self_hosted?
      "Import \"#{import.name}\" failed: #{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    else
      "Import \"#{import.name}\" failed, please contact us at hi@dawarich.com"
    end
  end
end

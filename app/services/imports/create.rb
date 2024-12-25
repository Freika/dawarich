# frozen_string_literal: true

class Imports::Create
  attr_reader :user, :import

  def initialize(user, import)
    @user = user
    @import = import
  end

  def call
    parser(import.source).new(import, user.id).call

    create_import_finished_notification(import, user)

    schedule_stats_creating(user.id)
    schedule_visit_suggesting(user.id, import)
    schedule_reverse_geocoding(user.id)
  rescue StandardError => e
    create_import_failed_notification(import, user, e)
  end

  private

  def parser(source)
    # Bad classes naming by the way, they are not parsers, they are point creators
    case source
    when 'google_semantic_history'      then GoogleMaps::SemanticHistoryParser
    when 'google_phone_takeout'         then GoogleMaps::PhoneTakeoutParser
    when 'owntracks'                    then OwnTracks::ExportParser
    when 'gpx'                          then Gpx::TrackParser
    when 'geojson'                      then Geojson::ImportParser
    when 'immich_api', 'photoprism_api' then Photos::ImportParser
    end
  end

  def schedule_stats_creating(user_id)
    import.years_and_months_tracked.each do |year, month|
      Stats::CalculatingJob.perform_later(user_id, year, month)
    end
  end

  def schedule_visit_suggesting(user_id, import)
    points = import.points.order(:timestamp)
    start_at = Time.zone.at(points.first.timestamp)
    end_at = Time.zone.at(points.last.timestamp)

    VisitSuggestingJob.perform_later(user_ids: [user_id], start_at:, end_at:)
  end

  def schedule_reverse_geocoding(user_id)
    EnqueueBackgroundJob.perform_later('continue_reverse_geocoding', user_id)
  end

  def create_import_finished_notification(import, user)
    Notifications::Create.new(
      user:,
      kind: :info,
      title: 'Import finished',
      content: "Import \"#{import.name}\" successfully finished."
    ).call
  end

  def create_import_failed_notification(import, user, error)
    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Import failed',
      content: "Import \"#{import.name}\" failed: #{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    ).call
  end
end

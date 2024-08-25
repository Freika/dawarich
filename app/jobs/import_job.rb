# frozen_string_literal: true

class ImportJob < ApplicationJob
  queue_as :imports

  def perform(user_id, import_id)
    user = User.find(user_id)
    import = user.imports.find(import_id)

    result = parser(import.source).new(import, user_id).call

    import.update(
      raw_points: result[:raw_points], doubles: result[:doubles], processed: result[:processed]
    )

    create_import_finished_notification(import, user)

    schedule_stats_creating(user_id)
    schedule_visit_suggesting(user_id, import)
  rescue StandardError => e
    create_import_failed_notification(import, user, e)
  end

  private

  def parser(source)
    # Bad classes naming by the way, they are not parsers, they are point creators
    case source
    when 'google_semantic_history'  then GoogleMaps::SemanticHistoryParser
    when 'google_records'           then GoogleMaps::RecordsParser
    when 'google_phone_takeout'     then GoogleMaps::PhoneTakeoutParser
    when 'owntracks'                then OwnTracks::ExportParser
    when 'gpx'                      then Gpx::TrackParser
    when 'immich_api'               then Immich::ImportParser
    end
  end

  def schedule_stats_creating(user_id)
    StatCreatingJob.perform_later(user_id)
  end

  def schedule_visit_suggesting(user_id, import)
    points = import.points.order(:timestamp)
    start_at = Time.zone.at(points.first.timestamp)
    end_at = Time.zone.at(points.last.timestamp)

    VisitSuggestingJob.perform_later(user_ids: [user_id], start_at:, end_at:)
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

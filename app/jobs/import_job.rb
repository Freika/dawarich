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

    Notifications::Create.new(
      user:,
      kind: :info,
      title: 'Import finished',
      content: "Import \"#{import.name}\" successfully finished."
    ).call

    StatCreatingJob.perform_later(user_id)
  rescue StandardError => e
    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Import failed',
      content: "Import \"#{import.name}\" failed: #{e.message}"
    ).call
  end

  private

  def parser(source)
    case source
    when 'google_semantic_history'  then GoogleMaps::SemanticHistoryParser
    when 'google_records'           then GoogleMaps::RecordsParser
    when 'google_phone_takeout'     then GoogleMaps::PhoneTakeoutParser
    when 'owntracks'                then OwnTracks::ExportParser
    when 'gpx'                      then Gpx::TrackParser
    end
  end
end

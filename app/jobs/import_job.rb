# frozen_string_literal: true

class ImportJob < ApplicationJob
  queue_as :imports

  def perform(user_id, import_id)
    user = User.find(user_id)
    import = user.imports.find(import_id)

    result = parser(import.source).new(import).call

    import.update(
      raw_points: result[:raw_points], doubles: result[:doubles], processed: result[:processed]
    )

    StatCreatingJob.perform_later(user_id)
  end

  private

  def parser(source)
    case source
    when 'google' then GoogleMaps::TimelineParser
    when 'owntracks' then OwnTracks::ExportParser
    end
  end
end

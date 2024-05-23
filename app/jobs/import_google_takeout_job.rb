# frozen_string_literal: true

class ImportGoogleTakeoutJob < ApplicationJob
  queue_as :imports

  def perform(import_id, json_string)
    import = Import.find(import_id)

    json = Oj.load(json_string)

    GoogleMaps::RecordsParser.new(import).call(json)
  end
end

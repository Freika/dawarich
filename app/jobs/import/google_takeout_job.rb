# frozen_string_literal: true

class Import::GoogleTakeoutJob < ApplicationJob
  queue_as :imports
  sidekiq_options retry: false

  def perform(import_id, json_string)
    import = Import.find(import_id)

    json = Oj.load(json_string)

    GoogleMaps::RecordsParser.new(import).call(json)
  end
end

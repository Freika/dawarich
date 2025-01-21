# frozen_string_literal: true

class Import::GoogleTakeoutJob < ApplicationJob
  queue_as :imports
  sidekiq_options retry: false

  def perform(import_id, json_array)
    import = Import.find(import_id)
    records = Oj.load(json_array)

    GoogleMaps::RecordsParser.new(import).call(records)
  end
end

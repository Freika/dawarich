# frozen_string_literal: true

class Import::GoogleTakeoutJob < ApplicationJob
  queue_as :imports

  def perform(import_id, locations, current_index)
    locations_batch = Oj.load(locations)
    import = Import.find(import_id)

    GoogleMaps::RecordsImporter.new(import, current_index).call(locations_batch)
  end
end

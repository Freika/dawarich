# frozen_string_literal: true

class ExportJob < ApplicationJob
  queue_as :exports

  def perform(export_id, start_at, end_at, format: :geojson)
    export = Export.find(export_id)

    Exports::Create.new(export:, start_at:, end_at:, format:).call
  end
end

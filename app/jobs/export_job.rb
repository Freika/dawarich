# frozen_string_literal: true

class ExportJob < ApplicationJob
  queue_as :exports

  def perform(export_id, start_at, end_at, file_format: :json)
    export = Export.find(export_id)

    Exports::Create.new(export:, start_at:, end_at:, file_format:).call
  end
end

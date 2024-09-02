# frozen_string_literal: true

class ExportJob < ApplicationJob
  queue_as :exports

  def perform(export_id, start_at, end_at)
    export = Export.find(export_id)

    Exports::Create.new(export:, start_at:, end_at:).call
  end
end

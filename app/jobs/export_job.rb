# frozen_string_literal: true

class ExportJob < ApplicationJob
  queue_as :exports

  def perform(export_id)
    export = Export.find(export_id)

    Exports::Create.new(export:).call
  end
end

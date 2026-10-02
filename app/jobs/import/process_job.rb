# frozen_string_literal: true

class Import::ProcessJob < ApplicationJob
  queue_as :imports
  retry_on Imports::GpxLegacy::Busy, wait: 5.seconds, attempts: :unlimited

  def perform(import_id)
    import = Import.find(import_id)

    Imports::GpxLegacy.perform(import, event_id: job_id)
  end
end

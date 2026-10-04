# frozen_string_literal: true

class Import::ProcessJob < ApplicationJob
  queue_as :imports

  retry_on Imports::GpxLegacy::Busy, Imports::NormalLegacy::Busy, wait: :polynomially_longer,
                                     attempts: Imports::BusyRetry::ATTEMPTS do |job, _error|
    Imports::BusyRetry.fail!(job.arguments.first, from: %i[created processing])
  end

  def perform(import_id)
    import = Import.find(import_id)
    return Imports::NormalLegacy.perform(import, event_id: job_id) unless import.gpx?

    Imports::GpxLegacy.perform(import, event_id: job_id)
  end
end

# frozen_string_literal: true

class Import::ProcessJob < ApplicationJob
  queue_as :imports

  retry_on Imports::GpxLegacy::Busy, wait: :polynomially_longer,
                                     attempts: Imports::BusyRetry::ATTEMPTS do |job, _error|
    Imports::BusyRetry.fail!(job.arguments.first, from: %i[created processing])
  end

  def perform(import_id)
    import = Import.find(import_id)
    return I18n.with_locale(import.user.locale) { import.process! } unless import.gpx?

    Imports::GpxLegacy.perform(import, event_id: job_id)
  end
end

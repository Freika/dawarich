# frozen_string_literal: true

class Import::NormalResumeJob < ApplicationJob
  queue_as :imports

  retry_on Imports::NormalResume::Busy, wait: :polynomially_longer,
                                     attempts: Imports::BusyRetry::ATTEMPTS do |job, _error|
    payload = job.arguments.first
    Imports::BusyRetry.fail!(payload.fetch('import_id'), from: %i[created processing],
                                                         user_id: payload.fetch('user_id'))
  end

  delegate :perform, to: :'Imports::NormalResume'
end

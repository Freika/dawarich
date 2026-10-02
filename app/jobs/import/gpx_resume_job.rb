# frozen_string_literal: true

class Import::GpxResumeJob < ApplicationJob
  queue_as :imports
  retry_on Imports::GpxResume::Busy, wait: 5.seconds, attempts: :unlimited

  delegate :perform, to: :'Imports::GpxResume'
end

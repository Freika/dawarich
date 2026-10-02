# frozen_string_literal: true

class Import::GpxResumeJob < ApplicationJob
  queue_as :imports

  delegate :perform, to: :'Imports::GpxResume'
end

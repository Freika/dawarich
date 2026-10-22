# frozen_string_literal: true

module Resumable
  extend ActiveSupport::Concern

  MAX_RESUMPTIONS = 500
  RESUME_WAIT = 30.seconds

  included do
    include ActiveJob::Continuable

    self.max_resumptions = MAX_RESUMPTIONS
    self.resume_options = { wait: RESUME_WAIT }
    self.resume_errors_after_advancing = false
  end
end

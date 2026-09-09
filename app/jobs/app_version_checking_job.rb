# frozen_string_literal: true

class AppVersionCheckingJob < ApplicationJob
  queue_as :app_version_checking
  sidekiq_options retry: false

  def perform
    CheckAppVersion.new.refresh
  end
end

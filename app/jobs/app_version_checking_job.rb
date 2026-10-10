# frozen_string_literal: true

class AppVersionCheckingJob < ApplicationJob
  queue_as :app_version_checking
  sidekiq_options retry: false

  def perform
    check = CheckAppVersion.new
    latest = check.fetch_latest
    return unless latest

    JobOwnership.with_owner('cron:app_version_checking_job') { check.store(latest) }
  end
end

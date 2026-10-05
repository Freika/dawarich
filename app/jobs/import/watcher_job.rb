# frozen_string_literal: true

class Import::WatcherJob < ApplicationJob
  queue_as :imports
  sidekiq_options retry: false

  def perform
    return unless DawarichSettings.self_hosted?

    JobOwnership.with_owner('cron:watcher_job') { Imports::Watcher.new.call }
  end
end

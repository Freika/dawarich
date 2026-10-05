# frozen_string_literal: true

class Import::WatcherJob < ApplicationJob
  queue_as :imports
  sidekiq_options retry: false

  def perform
    return unless DawarichSettings.self_hosted?

    return if JobOwnership.oban?('cron:watcher_job')

    Imports::Watcher.new.call(owner_key: 'cron:watcher_job')
  end
end

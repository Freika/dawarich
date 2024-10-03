# frozen_string_literal: true

class Import::WatcherJob < ApplicationJob
  queue_as :imports
  sidekiq_options retry: false

  def perform
    Imports::Watcher.new.call
  end
end

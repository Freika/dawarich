# frozen_string_literal: true

class Import::WatcherJob < ApplicationJob
  queue_as :imports

  def perform
    Imports::Watcher.new.call
  end
end

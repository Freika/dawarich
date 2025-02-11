# frozen_string_literal: true

class Cache::CleaningJob < ApplicationJob
  queue_as :default

  def perform
    Cache::Clean.call
  end
end

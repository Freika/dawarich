# frozen_string_literal: true

class Cache::CleaningJob < ApplicationJob
  queue_as :cache

  def perform
    Cache::Clean.call
  end
end

# frozen_string_literal: true

class Exploration::InstallGeographyJob < ApplicationJob
  queue_as :achievements

  def self.schedule
    claimed = Sidekiq.redis { |redis| redis.set('exploration:install-geography', 1, nx: true, ex: 1.hour.to_i) }
    perform_later if claimed
  rescue StandardError
    Sidekiq.redis { |redis| redis.del('exploration:install-geography') }
    raise
  end

  def perform
    Exploration::Geography.install!
  ensure
    Sidekiq.redis { |redis| redis.del('exploration:install-geography') }
  end
end

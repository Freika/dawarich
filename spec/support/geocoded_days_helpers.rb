# frozen_string_literal: true

module GeocodedDaysHelpers
  def clear_geocoded_days
    Sidekiq.redis do |redis|
      members = redis.call('ZRANGE', Stats::GeocodedDays::PENDING_KEY, 0, -1)
      keys = members.map { |member| "#{Stats::GeocodedDays::VERSION_KEY_PREFIX}:#{member}" }
      redis.call('DEL', Stats::GeocodedDays::PENDING_KEY, *keys)
    end
  end
end

RSpec.configure { |config| config.include GeocodedDaysHelpers }

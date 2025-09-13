# frozen_string_literal: true

class Cache::PreheatingJob < ApplicationJob
  queue_as :cache

  def perform
    User.find_each do |user|
      Rails.cache.write(
        "dawarich/user_#{user.id}_years_tracked",
        user.years_tracked,
        expires_in: 1.day
      )

      Rails.cache.write(
        "dawarich/user_#{user.id}_points_geocoded_stats",
        StatsQuery.new(user).cached_points_geocoded_stats,
        expires_in: 1.day
      )

      Rails.cache.write(
        "dawarich/user_#{user.id}_countries_visited",
        user.countries_visited_uncached,
        expires_in: 1.day
      )

      Rails.cache.write(
        "dawarich/user_#{user.id}_cities_visited",
        user.cities_visited_uncached,
        expires_in: 1.day
      )
    end
  end
end

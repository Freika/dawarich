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

      # Preheat total_distance cache
      total_distance_meters = user.stats.sum(:distance)
      Rails.cache.write(
        "dawarich/user_#{user.id}_total_distance",
        Stat.convert_distance(total_distance_meters, user.safe_settings.distance_unit),
        expires_in: 1.day
      )

      # Preheat insights yearly digest cache for recent years
      preheat_insights_digests(user)
    end
  end

  private

  def preheat_insights_digests(user)
    # Get years that have stats data
    years = user.stats.distinct.pluck(:year).sort.reverse.first(2) # Current + previous year
    return if years.empty?

    years.each do |year|
      digest = user.digests.yearly.find_by(year: year)

      # Calculate digest if it doesn't exist or is stale
      if digest.nil? || digest_stale?(user, digest, year)
        digest = Users::Digests::CalculateYear.new(user.id, year).call
      end

      next unless digest

      # Cache the digest with timestamp-based key
      cache_key = "insights/yearly_digest/#{user.id}/#{year}/#{digest.updated_at.to_i}"
      Rails.cache.write(cache_key, digest, expires_in: 1.hour)
    end
  rescue StandardError => e
    Rails.logger.error("Failed to preheat insights digest for user #{user.id}: #{e.message}")
  end

  def digest_stale?(user, digest, year)
    return true if digest.travel_patterns.blank?

    latest_stat_update = user.stats.where(year: year).maximum(:updated_at)
    return false if latest_stat_update.nil?

    digest.updated_at < latest_stat_update
  end
end

# frozen_string_literal: true

class Cache::PreheatInsightsDigests
  # Preheats the insights yearly digest cache for a user.
  # This should be called during cache preheating to ensure
  # fast Insights page loads.
  def initialize(user)
    @user = user
  end

  def call
    years = recent_years_with_stats
    return if years.empty?

    years.each { |year| preheat_year(year) }
  rescue StandardError => e
    Rails.logger.error("Failed to preheat insights digest for user #{user.id}: #{e.message}")
  end

  private

  attr_reader :user

  def recent_years_with_stats
    # Preheat current + previous year (most commonly viewed)
    user.stats.distinct.pluck(:year).sort.reverse.first(2)
  end

  def preheat_year(year)
    digest = user.digests.yearly.find_by(year: year)

    # Calculate digest if it doesn't exist or is stale
    digest = Users::Digests::CalculateYear.new(user.id, year).call if digest.nil? || digest_stale?(digest, year)

    return unless digest

    # Cache the digest with timestamp-based key
    cache_key = "insights/yearly_digest/#{user.id}/#{year}/#{digest.updated_at.to_i}"
    Rails.cache.write(cache_key, digest, expires_in: 1.hour)
  end

  def digest_stale?(digest, year)
    return true if digest.travel_patterns.blank?

    latest_stat_update = user.stats.where(year: year).maximum(:updated_at)
    return false if latest_stat_update.nil?

    digest.updated_at < latest_stat_update
  end
end

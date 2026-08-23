# frozen_string_literal: true

# Nightly cache preheat. Writes the one global cache entry inline, then fans
# out per-user work so the run is bounded by the slowest single user rather
# than by the sum of every user.
class Cache::PreheatingJob < ApplicationJob
  queue_as :cache

  BATCH_SIZE = 500

  def perform
    preheat_country_borders

    target_users.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      ActiveJob.perform_all_later(batch.map { |user| Cache::UserPreheatingJob.new(user.id) })
    end
  end

  private

  # Self-hosted instances have no subscription lifecycle, so every user is
  # worth preheating. On Cloud, warming caches for lapsed accounts that will
  # never load a page is wasted queue time.
  def target_users
    scope = User.select(:id)

    DawarichSettings.self_hosted? ? scope : scope.active_or_trial
  end

  def preheat_country_borders
    Rails.cache.write(
      'dawarich/countries_codes',
      Oj.load(File.read(Rails.root.join('lib/assets/countries.geojson'))),
      expires_in: Cache::UserPreheatingJob::EXPIRES_IN
    )
  end
end

# frozen_string_literal: true

class DataMigrations::BackfillAchievementsJob < ApplicationJob
  queue_as :data_migrations

  def perform
    return if Country.none?

    Achievements::LoadRegions.new.call if regions_missing?
    Achievements::BulkCheckJob.perform_later(notify: false, force: true, stale_only: true)
  end

  private

  def regions_missing?
    codes = Achievements::Registry.subdivision_codes
    Region.where(code: codes).count < codes.size
  end
end

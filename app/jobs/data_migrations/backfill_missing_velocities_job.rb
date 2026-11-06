# frozen_string_literal: true

class DataMigrations::BackfillMissingVelocitiesJob < ApplicationJob
  queue_as :low_priority

  SOURCES = %i[kml gpx geojson].freeze

  def perform(import_id = nil)
    return enqueue_imports if import_id.nil?

    import = Import.find_by(id: import_id)
    user = import && find_user_or_skip(import.user_id)
    return unless user

    if Points::VelocityFiller.recorded_speed?(import.id)
      Rails.logger.info("[DataMigrations::BackfillMissingVelocities] import_id=#{import.id} skipped=recorded_speeds")
      return
    end

    filled = Point.transaction(requires_new: true) do
      fill_flyovers(import).tap do |result|
        recalculate_months(user, result.flyover_timestamps)
        recalculate_trips(user, result.flyover_timestamps)
      end
    end
    Points::TileEpoch.bump_range(user.id, filled.first_timestamp, filled.last_timestamp) if filled.updated.positive?
    Rails.logger.info("[DataMigrations::BackfillMissingVelocities] import_id=#{import.id} updated=#{filled.updated}")
  end

  private

  def enqueue_imports
    ids = Import.where(source: SOURCES).ids
    ActiveJob.perform_all_later(ids.map { |id| self.class.new(id) })
    Rails.logger.info("[DataMigrations::BackfillMissingVelocities] enqueued=#{ids.size}")
  end

  def fill_flyovers(import)
    flyover_speed = CountriesAndCities::FLYOVER_VELOCITY_THRESHOLD_KMH / CountriesAndCities::MS_TO_KMH
    Points::VelocityFiller.new(import.id, zero_is_missing: true, minimum_speed: flyover_speed).call
  end

  def recalculate_months(user, timestamps)
    months = timestamps.map { |timestamp| Time.at(timestamp).in_time_zone(user.timezone_iana) }
                       .map { |time| [time.year, time.month] }.uniq.sort
    Stats::RecalculateMonths.new(user, months).call
  end

  def recalculate_trips(user, timestamps)
    return if timestamps.empty?

    first, last = timestamps.minmax.map { |timestamp| Time.zone.at(timestamp) }
    user.trips.where(started_at: ..last, ended_at: first..).find_each do |trip|
      trip.calculate_countries
      trip.update_column(:visited_countries, trip.visited_countries)
    end
  end
end

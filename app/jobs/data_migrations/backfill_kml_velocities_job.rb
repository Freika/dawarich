# frozen_string_literal: true

class DataMigrations::BackfillKmlVelocitiesJob < ApplicationJob
  queue_as :low_priority

  UPDATE_BATCH_SIZE = 1000

  def perform(import_id = nil)
    return enqueue_imports if import_id.nil?

    import = Import.find_by(id: import_id)
    user = import && find_user_or_skip(import.user_id)
    return unless user

    changed = Point.transaction(requires_new: true) do
      backfill(import).tap do |points|
        flyovers = flyover_timestamps(points)
        recalculate_months(user, flyovers)
        recalculate_trips(user, flyovers)
      end
    end
    Points::TileEpoch.bump(user.id, timestamps: changed.map { |point| point[:timestamp] }) if changed.any?
    Rails.logger.info("[DataMigrations::BackfillKmlVelocities] import_id=#{import.id} updated=#{changed.size}")
  end

  private

  def enqueue_imports
    ids = Import.kml.ids
    ActiveJob.perform_all_later(ids.map { |id| self.class.new(id) })
    Rails.logger.info("[DataMigrations::BackfillKmlVelocities] enqueued=#{ids.size}")
  end

  def backfill(import)
    points = Point.where(import_id: import.id)
                  .pluck(:id, :timestamp, :velocity, Arel.sql('ST_AsText(lonlat)'))
                  .map { |id, timestamp, velocity, lonlat| { id:, timestamp:, velocity: velocity.to_f, lonlat: } }
    unless points.all? { |point| point[:velocity].zero? }
      Rails.logger.info("[DataMigrations::BackfillKmlVelocities] import_id=#{import.id} skipped=recorded_speeds")
      return []
    end

    points.each { |point| point[:velocity] = nil }
    Kml::VelocityFiller.call(points)
    changed = points.reject { |point| point[:velocity].zero? }
    changed.each_slice(UPDATE_BATCH_SIZE) { |batch| update_velocities(batch) }
    changed
  end

  def update_velocities(batch)
    values = batch.map { |point| "(#{Integer(point[:id])}, '#{Float(point[:velocity])}')" }.join(', ')
    Point.connection.execute(<<~SQL.squish)
      UPDATE points SET velocity = updates.velocity
      FROM (VALUES #{values}) AS updates(id, velocity)
      WHERE points.id = updates.id
    SQL
  end

  def flyover_timestamps(points)
    points.filter_map do |point|
      flyover = point[:velocity] * CountriesAndCities::MS_TO_KMH > CountriesAndCities::FLYOVER_VELOCITY_THRESHOLD_KMH
      point[:timestamp] if flyover
    end
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

# frozen_string_literal: true

class DataMigrations::BackfillKmlVelocitiesJob < ApplicationJob
  queue_as :low_priority

  UPDATE_BATCH_SIZE = 1000

  def perform(import_id = nil)
    return enqueue_imports if import_id.nil?

    import = Import.find_by(id: import_id)
    return unless import

    changed = backfill(import)
    return if changed.empty?

    recalculate(import.user, changed.map { |point| point[:timestamp] })
    Rails.logger.info("[DataMigrations::BackfillKmlVelocities] import_id=#{import.id} updated=#{changed.size}")
  end

  private

  def enqueue_imports
    ActiveJob.perform_all_later(Import.kml.ids.map { |id| self.class.new(id) })
  end

  def backfill(import)
    points = Point.where(import_id: import.id)
                  .pluck(:id, :timestamp, :velocity, Arel.sql('ST_AsText(lonlat)'))
                  .map { |id, timestamp, velocity, lonlat| { id:, timestamp:, velocity: velocity.to_f, lonlat: } }
    missing = points.select { |point| point[:velocity].zero? }

    Kml::VelocityFiller.call(points)
    changed = missing.reject { |point| point[:velocity].zero? }
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

  def recalculate(user, timestamps)
    months = timestamps.map { |timestamp| Time.zone.at(timestamp) }.map { |time| [time.year, time.month] }.uniq
    months.each { |year, month| Stats::CalculateMonth.new(user.id, year, month, notify_on_failure: false).call }
    refresh_existing_digests(user, months)

    first, last = timestamps.minmax.map { |timestamp| Time.zone.at(timestamp) }
    user.trips.where(started_at: ..last, ended_at: first..).find_each do |trip|
      Trips::CalculateCountriesJob.perform_later(trip.id, user.safe_settings.distance_unit)
    end
  end

  def refresh_existing_digests(user, months)
    months.each do |year, month|
      Users::Digests::CalculateMonth.new(user.id, year, month).call if user.digests.monthly.exists?(year:, month:)
    end
    months.map(&:first).uniq.each do |year|
      Users::Digests::CalculateYear.new(user.id, year).call if user.digests.yearly.exists?(year:)
    end
  end
end

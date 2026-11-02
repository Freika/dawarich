# frozen_string_literal: true

# The db/schema.rb shipped with 1.5.0–1.6.x predates the rewrite of
# 20260323000001, so instances first set up from that schema recorded the
# migration as applied without ever getting points.altitude_decimal. Since
# 1.20.0 the points triggers read it, and every point write failed there.
class EnsurePointsAltitudeDecimal < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LOCK_TIMEOUT = '5s'
  MAX_ATTEMPTS = 5

  def up
    return if column_exists?(:points, :altitude_decimal)

    add_altitude_decimal
    Point.reset_column_information
  end

  def down; end

  private

  # Nullable and without a default, so the ALTER is metadata-only; readers
  # fall back to points.altitude while the new column is empty.
  def add_altitude_decimal
    attempts = 0

    begin
      attempts += 1
      transaction do
        execute "SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'"
        execute 'ALTER TABLE points ADD COLUMN IF NOT EXISTS altitude_decimal numeric(10,2)'
      end
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::QueryAborted => e
      if attempts >= MAX_ATTEMPTS
        raise e.class, "points.altitude_decimal is still missing after #{MAX_ATTEMPTS} attempts (#{e.message}). " \
                       'A long transaction holds points: stop Sidekiq and restart, or run ' \
                       'ALTER TABLE points ADD COLUMN IF NOT EXISTS altitude_decimal numeric(10,2) once it ends.'
      end

      sleep(attempts * 5)
      retry
    end
  end
end

# frozen_string_literal: true

class DataMigrations::BackfillSpeedJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 50_000

  def perform(batch_size: BATCH_SIZE)
    Rails.logger.info('[BackfillSpeedJob] Starting speed backfill from velocity')

    total = 0

    loop do
      rows = Point.connection.update(<<~SQL.squish)
        UPDATE points
        SET speed = velocity::float
        WHERE id IN (
          SELECT id FROM points
          WHERE speed IS NULL
            AND velocity IS NOT NULL
            AND velocity ~ '^-?\\d+\\.?\\d*$'
          LIMIT #{batch_size}
        )
      SQL

      total += rows
      Rails.logger.info("[BackfillSpeedJob] Backfilled #{total} points so far")
      break if rows < batch_size
    end

    Rails.logger.info("[BackfillSpeedJob] Completed. Total points backfilled: #{total}")
  end
end

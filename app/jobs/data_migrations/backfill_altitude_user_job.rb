# frozen_string_literal: true

# Per-user altitude backfill. Processes non-archived points via PK cursor,
# then streams each archive. Designed for 41M+ point databases:
# - PK cursor avoids seq scan and offset drift
# - Only selects id, altitude, raw_data (no lonlat, geodata, etc.)
# - Archives streamed line-by-line (no full decompression in memory)
# - Per-user scope keeps each job small and retryable
class DataMigrations::BackfillAltitudeUserJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 1000

  def perform(user_id, batch_size: BATCH_SIZE)
    Rails.logger.info("Backfilling altitude for user #{user_id}")

    stats = { updated: 0, skipped: 0, archived: 0 }

    backfill_from_raw_data(user_id, batch_size, stats)
    backfill_from_archives(user_id, batch_size, stats)

    Rails.logger.info("Altitude backfill for user #{user_id} complete: #{stats}")
  end

  private

  # PK-cursor walk: fetches batch_size rows ordered by ID, then uses the last ID
  # to fetch the next batch. O(batch_size) per query via the PK index — no seq scan.
  def backfill_from_raw_data(user_id, batch_size, stats)
    last_id = 0

    loop do
      points = Point
               .where(user_id: user_id)
               .where.not(raw_data: {})
               .where('id > ?', last_id)
               .order(:id)
               .limit(batch_size)
               .select(:id, :altitude, :raw_data)

      break if points.empty?

      updates = points.filter_map { |point| build_update(point) }

      if updates.any?
        Point.upsert_all(updates, unique_by: :id, update_only: [:altitude])
        stats[:updated] += updates.size
      end

      stats[:skipped] += points.size - updates.size
      last_id = points.last.id
    end
  end

  def backfill_from_archives(user_id, batch_size, stats)
    Points::RawDataArchive.where(user_id: user_id).find_each do |archive|
      process_archive(archive, batch_size, stats)
    rescue StandardError => e
      Rails.logger.error("Failed to process archive #{archive.id}: #{e.message}")
    end
  end

  def process_archive(archive, batch_size, stats)
    return unless archive.file.attached?

    updates = []

    stream_archive_lines(archive) do |line|
      data = JSON.parse(line)
      altitude = Points::AltitudeExtractor.from_raw_data(data['raw_data'])
      next if altitude.nil?

      updates << { id: data['id'], altitude: altitude }

      if updates.size >= batch_size
        flush_updates(updates, stats)
        updates = []
      end
    end

    flush_updates(updates, stats) if updates.any?
  end

  def flush_updates(updates, stats)
    point_ids = updates.map { |u| u[:id] }
    existing = Point.where(id: point_ids).pluck(:id, :altitude).to_h

    meaningful_updates = updates.select do |u|
      next false unless existing.key?(u[:id])

      current = existing[u[:id]]
      current.nil? || current.to_d != BigDecimal(u[:altitude].to_s)
    end

    return unless meaningful_updates.any?

    Point.upsert_all(meaningful_updates, unique_by: :id, update_only: [:altitude])
    stats[:archived] += meaningful_updates.size
  end

  def build_update(point)
    altitude = Points::AltitudeExtractor.from_raw_data(point.raw_data)
    return nil if altitude.nil?
    return nil if point.altitude.present? && point.altitude.to_d == BigDecimal(altitude.to_s)

    { id: point.id, altitude: altitude }
  end

  # Streams archive line-by-line without materializing the full decompressed content.
  def stream_archive_lines(archive, &block)
    encrypted = archive.file.blob.download
    decrypted = Points::RawData::Encryption.decrypt_if_needed(encrypted, archive)

    gz = Zlib::GzipReader.new(StringIO.new(decrypted))
    gz.each_line(&block)
    gz.close
  end
end

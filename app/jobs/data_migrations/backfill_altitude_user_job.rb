# frozen_string_literal: true

class DataMigrations::BackfillAltitudeUserJob < ApplicationJob
  include Resumable

  queue_as :data_migrations

  BATCH_SIZE = 1000

  def perform(user_id, batch_size: BATCH_SIZE)
    Rails.logger.info("Backfilling altitude for user #{user_id}")

    stats = { updated: 0, skipped: 0, archived: 0 }

    step :backfill_from_raw_data, start: 0 do |step|
      backfill_from_raw_data(user_id, batch_size, stats, step)
    end

    step :backfill_from_archives, start: 0 do |step|
      backfill_from_archives(user_id, batch_size, stats, step)
    end

    Rails.logger.info("Altitude backfill for user #{user_id} complete: #{stats}")
  end

  private

  def backfill_from_raw_data(user_id, batch_size, stats, step)
    loop do
      points = Point
               .where(user_id: user_id)
               .where.not(raw_data: {})
               .where('id > ?', step.cursor)
               .order(:id)
               .limit(batch_size)
               .select(:id, :altitude, :raw_data)

      break if points.empty?

      updates = points.filter_map { |point| build_update(point) }.to_h

      if updates.any?
        Points::BatchUpdate.column(:altitude, updates, cast: 'real')
        stats[:updated] += updates.size
      end

      stats[:skipped] += points.size - updates.size
      step.set!(points.last.id)
    end
  end

  def backfill_from_archives(user_id, batch_size, stats, step)
    loop do
      archives = Points::RawDataArchive
                 .where(user_id: user_id)
                 .where('id > ?', step.cursor)
                 .order(:id)
                 .limit(batch_size)

      break if archives.empty?

      archives.each do |archive|
        process_archive(archive, batch_size, stats)
      rescue StandardError => e
        Rails.logger.error("Failed to process archive #{archive.id}: #{e.message}")
      end

      step.set!(archives.last.id)
    end
  end

  def process_archive(archive, batch_size, stats)
    return unless archive.file.attached?

    updates = {}

    stream_archive_lines(archive) do |line|
      data = JSON.parse(line)
      altitude = Points::AltitudeExtractor.from_raw_data(data['raw_data'])
      next if altitude.nil?

      updates[data['id']] = altitude

      if updates.size >= batch_size
        flush_updates(updates, stats)
        updates = {}
      end
    end

    flush_updates(updates, stats) if updates.any?
  end

  def flush_updates(updates, stats)
    existing = Point.where(id: updates.keys).pluck(:id, :altitude).to_h

    meaningful_updates = updates.select do |id, altitude|
      next false unless existing.key?(id)

      current = existing[id]
      current.nil? || current.to_d != BigDecimal(altitude.to_s)
    end

    return unless meaningful_updates.any?

    Points::BatchUpdate.column(:altitude, meaningful_updates, cast: 'real')
    stats[:archived] += meaningful_updates.size
  end

  def build_update(point)
    altitude = Points::AltitudeExtractor.from_raw_data(point.raw_data)
    return nil if altitude.nil?
    return nil if point.altitude.present? && point.altitude.to_d == BigDecimal(altitude.to_s)

    [point.id, altitude]
  end

  def stream_archive_lines(archive, &block)
    encrypted = archive.file.blob.download
    decrypted = Points::RawData::Encryption.decrypt_if_needed(encrypted, archive)

    gz = Zlib::GzipReader.new(StringIO.new(decrypted))
    gz.each_line(&block)
    gz.close
  end
end

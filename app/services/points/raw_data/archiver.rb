# frozen_string_literal: true

module Points
  module RawData
    class Archiver
      SAFE_ARCHIVE_LAG = 2.months

      def initialize
        @stats = { processed: 0, archived: 0, failed: 0 }
      end

      def call
        unless archival_enabled?
          Rails.logger.info('Raw data archival disabled (ARCHIVE_RAW_DATA != "true")')
          return @stats
        end

        Rails.logger.info('Starting points raw_data archival...')

        archivable_months.find_each do |month_data|
          process_month(month_data)
        end

        Rails.logger.info("Archival complete: #{@stats}")
        @stats
      end

      def archive_specific_month(user_id, year, month)
        month_data = {
          'user_id' => user_id,
          'year' => year,
          'month' => month
        }

        process_month(month_data)
      end

      private

      def archival_enabled?
        ENV['ARCHIVE_RAW_DATA'] == 'true'
      end

      def archivable_months
        # Only months 2+ months old with unarchived points
        safe_cutoff = Date.current.beginning_of_month - SAFE_ARCHIVE_LAG

        Point.select(
          'user_id',
          'EXTRACT(YEAR FROM to_timestamp(timestamp))::int as year',
          'EXTRACT(MONTH FROM to_timestamp(timestamp))::int as month',
          'COUNT(*) as unarchived_count'
        ).where(raw_data_archived: false)
         .where('to_timestamp(timestamp) < ?', safe_cutoff)
         .group('user_id, EXTRACT(YEAR FROM to_timestamp(timestamp)), EXTRACT(MONTH FROM to_timestamp(timestamp))')
      end

      def process_month(month_data)
        user_id = month_data['user_id']
        year = month_data['year']
        month = month_data['month']

        lock_key = "archive_points:#{user_id}:#{year}:#{month}"

        # Advisory lock prevents duplicate processing
        ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds: 0) do
          archive_month(user_id, year, month)
          @stats[:processed] += 1
        end
      rescue ActiveRecord::AdvisoryLockError
        Rails.logger.info("Skipping #{lock_key} - already locked")
      rescue StandardError => e
        Rails.logger.error("Archive failed for #{user_id}/#{year}/#{month}: #{e.message}")
        Sentry.capture_exception(e) if defined?(Sentry)
        @stats[:failed] += 1
      end

      def archive_month(user_id, year, month)
        # Calculate timestamp range for the month
        start_of_month = Time.new(year, month, 1).to_i
        end_of_month = (Time.new(year, month, 1) + 1.month).to_i

        # Find unarchived points for this month
        points = Point.where(
          user_id: user_id,
          raw_data_archived: false
        ).where(timestamp: start_of_month...end_of_month)
         .where.not(raw_data: nil)  # Skip already-NULLed points

        return if points.empty?

        point_ids = points.pluck(:id)

        Rails.logger.info("Archiving #{point_ids.count} points for user #{user_id}, #{year}-#{format('%02d', month)}")

        # Create archive chunk
        archive = create_archive_chunk(user_id, year, month, points, point_ids)

        # Atomically mark points and NULL raw_data
        Point.transaction do
          Point.where(id: point_ids).update_all(
            raw_data_archived: true,
            raw_data_archive_id: archive.id,
            raw_data: nil  # Reclaim space!
          )
        end

        @stats[:archived] += point_ids.count

        Rails.logger.info("✓ Archived chunk #{archive.chunk_number} (#{archive.size_mb} MB)")
      end

      def create_archive_chunk(user_id, year, month, points, point_ids)
        # Determine chunk number (append-only)
        chunk_number = Points::RawDataArchive
          .where(user_id: user_id, year: year, month: month)
          .maximum(:chunk_number).to_i + 1

        # Compress points data
        compressed_data = Points::RawData::ChunkCompressor.new(points).compress

        # Create archive record
        archive = Points::RawDataArchive.create!(
          user_id: user_id,
          year: year,
          month: month,
          chunk_number: chunk_number,
          point_count: point_ids.count,
          point_ids_checksum: calculate_checksum(point_ids),
          archived_at: Time.current,
          metadata: {
            format_version: 1,
            compression: 'gzip',
            archived_by: 'Points::RawData::Archiver'
          }
        )

        # Attach compressed file via ActiveStorage
        filename = "raw_data_#{user_id}_#{year}_#{format('%02d', month)}_chunk#{format('%03d', chunk_number)}.jsonl.gz"

        archive.file.attach(
          io: StringIO.new(compressed_data),
          filename: filename,
          content_type: 'application/gzip'
        )

        archive
      end

      def calculate_checksum(point_ids)
        Digest::SHA256.hexdigest(point_ids.sort.join(','))
      end
    end
  end
end

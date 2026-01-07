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

        archivable_months.each do |month_data|
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

        # Use raw SQL to avoid GROUP BY issues with ActiveRecord
        # Use AT TIME ZONE 'UTC' to ensure consistent timezone handling
        sql = <<-SQL.squish
          SELECT user_id,
                 EXTRACT(YEAR FROM (to_timestamp(timestamp) AT TIME ZONE 'UTC'))::int as year,
                 EXTRACT(MONTH FROM (to_timestamp(timestamp) AT TIME ZONE 'UTC'))::int as month,
                 COUNT(*) as unarchived_count
          FROM points
          WHERE raw_data_archived = false
            AND raw_data IS NOT NULL
            AND raw_data != '{}'
            AND to_timestamp(timestamp) < ?
          GROUP BY user_id,
                   EXTRACT(YEAR FROM (to_timestamp(timestamp) AT TIME ZONE 'UTC')),
                   EXTRACT(MONTH FROM (to_timestamp(timestamp) AT TIME ZONE 'UTC'))
        SQL

        ActiveRecord::Base.connection.exec_query(
          ActiveRecord::Base.sanitize_sql_array([sql, safe_cutoff])
        )
      end

      def process_month(month_data)
        user_id = month_data['user_id']
        year = month_data['year']
        month = month_data['month']

        lock_key = "archive_points:#{user_id}:#{year}:#{month}"

        # Advisory lock prevents duplicate processing
        # Returns false if lock couldn't be acquired (already locked)
        lock_acquired = ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds: 0) do
          archive_month(user_id, year, month)
          @stats[:processed] += 1
          true
        end

        Rails.logger.info("Skipping #{lock_key} - already locked") unless lock_acquired
      rescue StandardError => e
        ExceptionReporter.call(e, "Failed to archive points for user #{user_id}, #{year}-#{month}")

        @stats[:failed] += 1
      end

      def archive_month(user_id, year, month)
        points = find_archivable_points(user_id, year, month)
        return if points.empty?

        point_ids = points.pluck(:id)
        log_archival_start(user_id, year, month, point_ids.count)

        archive = create_archive_chunk(user_id, year, month, points, point_ids)

        # Immediate verification before marking points as archived
        verification_result = verify_archive_immediately(archive, point_ids)
        unless verification_result[:success]
          Rails.logger.error("Immediate verification failed: #{verification_result[:error]}")
          archive.destroy  # Cleanup failed archive
          raise StandardError, "Archive verification failed: #{verification_result[:error]}"
        end

        mark_points_as_archived(point_ids, archive.id)
        update_stats(point_ids.count)
        log_archival_success(archive)
      end

      def find_archivable_points(user_id, year, month)
        timestamp_range = month_timestamp_range(year, month)

        Point.where(user_id: user_id, raw_data_archived: false)
             .where(timestamp: timestamp_range)
             .where.not(raw_data: nil)
             .where.not(raw_data: '{}')
      end

      def month_timestamp_range(year, month)
        start_of_month = Time.utc(year, month, 1).to_i
        end_of_month = (Time.utc(year, month, 1) + 1.month).to_i
        start_of_month...end_of_month
      end

      def mark_points_as_archived(point_ids, archive_id)
        Point.transaction do
          Point.where(id: point_ids).update_all(
            raw_data_archived: true,
            raw_data_archive_id: archive_id
          )
        end
      end

      def update_stats(archived_count)
        @stats[:archived] += archived_count
      end

      def log_archival_start(user_id, year, month, count)
        Rails.logger.info("Archiving #{count} points for user #{user_id}, #{year}-#{format('%02d', month)}")
      end

      def log_archival_success(archive)
        Rails.logger.info("✓ Archived chunk #{archive.chunk_number} (#{archive.size_mb} MB)")
      end

      def create_archive_chunk(user_id, year, month, points, point_ids)
        # Determine chunk number (append-only)
        chunk_number = Points::RawDataArchive
                       .where(user_id: user_id, year: year, month: month)
                       .maximum(:chunk_number).to_i + 1

        # Compress points data and get count
        compression_result = Points::RawData::ChunkCompressor.new(points).compress
        compressed_data = compression_result[:data]
        actual_count = compression_result[:count]

        # Validate count: critical data integrity check
        expected_count = point_ids.count
        if actual_count != expected_count
          error_msg = "Archive count mismatch for user #{user_id} #{year}-#{format('%02d', month)}: " \
                      "expected #{expected_count} points, but only #{actual_count} were compressed"
          Rails.logger.error(error_msg)
          ExceptionReporter.call(StandardError.new(error_msg), error_msg)
          raise StandardError, error_msg
        end

        Rails.logger.info("✓ Compression validated: #{actual_count}/#{expected_count} points")

        # Create archive record
        archive = Points::RawDataArchive.create!(
          user_id: user_id,
          year: year,
          month: month,
          chunk_number: chunk_number,
          point_count: actual_count,  # Use actual count, not assumed
          point_ids_checksum: calculate_checksum(point_ids),
          archived_at: Time.current,
          metadata: {
            format_version: 1,
            compression: 'gzip',
            archived_by: 'Points::RawData::Archiver',
            expected_count: expected_count,
            actual_count: actual_count
          }
        )

        # Attach compressed file via ActiveStorage
        # Uses directory structure: raw_data_archives/:user_id/:year/:month/:chunk.jsonl.gz
        # The key parameter controls the actual storage path
        archive.file.attach(
          io: StringIO.new(compressed_data),
          filename: "#{format('%03d', chunk_number)}.jsonl.gz",
          content_type: 'application/gzip',
          key: "raw_data_archives/#{user_id}/#{year}/#{format('%02d', month)}/#{format('%03d', chunk_number)}.jsonl.gz"
        )

        archive
      end

      def calculate_checksum(point_ids)
        Digest::SHA256.hexdigest(point_ids.sort.join(','))
      end

      def verify_archive_immediately(archive, expected_point_ids)
        # Lightweight verification immediately after archiving
        # Ensures archive is valid before marking points as archived

        # 1. Verify file is attached
        unless archive.file.attached?
          return { success: false, error: 'File not attached' }
        end

        # 2. Verify file can be downloaded
        begin
          compressed_content = archive.file.blob.download
        rescue StandardError => e
          return { success: false, error: "File download failed: #{e.message}" }
        end

        # 3. Verify file size is reasonable
        if compressed_content.bytesize.zero?
          return { success: false, error: 'File is empty' }
        end

        # 4. Verify file can be decompressed and parse JSONL
        begin
          io = StringIO.new(compressed_content)
          gz = Zlib::GzipReader.new(io)
          archived_point_ids = []

          gz.each_line do |line|
            data = JSON.parse(line)
            archived_point_ids << data['id']
          end

          gz.close
        rescue StandardError => e
          return { success: false, error: "Decompression/parsing failed: #{e.message}" }
        end

        # 5. Verify point count matches
        if archived_point_ids.count != expected_point_ids.count
          return {
            success: false,
            error: "Point count mismatch in archive: expected #{expected_point_ids.count}, found #{archived_point_ids.count}"
          }
        end

        # 6. Verify point IDs checksum matches
        archived_checksum = calculate_checksum(archived_point_ids)
        expected_checksum = calculate_checksum(expected_point_ids)
        if archived_checksum != expected_checksum
          return { success: false, error: 'Point IDs checksum mismatch in archive' }
        end

        Rails.logger.info("✓ Immediate verification passed for archive #{archive.id}")
        { success: true }
      end
    end
  end
end

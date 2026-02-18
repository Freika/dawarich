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
        lock_key = "archive_points:#{user_id}:#{year}:#{month}"

        lock_acquired = ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds: 0) do
          archive_month(user_id, year, month)
          true
        end

        raise "Could not acquire lock for #{lock_key} — archival already in progress" unless lock_acquired
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

          # Report successful archive operation
          Metrics::Archives::Operation.new(
            operation: 'archive',
            status: 'success'
          ).call

          true
        end

        Rails.logger.info("Skipping #{lock_key} - already locked") unless lock_acquired
      rescue StandardError => e
        ExceptionReporter.call(e, "Failed to archive points for user #{user_id}, #{year}-#{month}")

        @stats[:failed] += 1

        # Report failed archive operation
        Metrics::Archives::Operation.new(
          operation: 'archive',
          status: 'failure'
        ).call
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
          archive.destroy # Cleanup failed archive
          raise StandardError, "Archive verification failed: #{verification_result[:error]}"
        end

        mark_points_as_archived(point_ids, archive.id)
        update_stats(point_ids.count)
        log_archival_success(archive)

        # Report points archived
        Metrics::Archives::PointsArchived.new(
          count: point_ids.count,
          operation: 'added'
        ).call
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
          # rubocop:disable Rails/SkipsModelValidations
          Point.where(id: point_ids).update_all(
            raw_data_archived: true,
            raw_data_archive_id: archive_id
          )
          # rubocop:enable Rails/SkipsModelValidations
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
          # Report count mismatch to metrics
          Metrics::Archives::CountMismatch.new(
            user_id: user_id,
            year: year,
            month: month,
            expected: expected_count,
            actual: actual_count
          ).call

          error_msg = "Archive count mismatch for user #{user_id} #{year}-#{format('%02d', month)}: " \
                      "expected #{expected_count} points, but only #{actual_count} were compressed"
          Rails.logger.error(error_msg)
          ExceptionReporter.call(StandardError.new(error_msg), error_msg)
          raise StandardError, error_msg
        end

        Rails.logger.info("✓ Compression validated: #{actual_count}/#{expected_count} points")

        # Encrypt compressed data (pipeline: JSONL → gzip → encrypt)
        encrypted_data = Encryption.encrypt(compressed_data)
        content_checksum = Digest::SHA256.hexdigest(encrypted_data)

        # Create archive record
        chunk_filename = "#{format('%03d', chunk_number)}.jsonl.gz.enc"
        archive = Points::RawDataArchive.create!(
          user_id: user_id,
          year: year,
          month: month,
          chunk_number: chunk_number,
          point_count: actual_count,
          point_ids_checksum: calculate_checksum(point_ids),
          archived_at: Time.current,
          metadata: {
            format_version: 2,
            compression: 'gzip',
            encryption: 'aes-256-gcm',
            content_checksum: content_checksum,
            archived_by: 'Points::RawData::Archiver',
            expected_count: expected_count,
            actual_count: actual_count
          }
        )

        # Attach encrypted file via ActiveStorage
        storage_key = "raw_data_archives/#{user_id}/#{year}/#{format('%02d', month)}/#{chunk_filename}"
        archive.file.attach(
          io: StringIO.new(encrypted_data),
          filename: chunk_filename,
          content_type: 'application/octet-stream',
          key: storage_key
        )

        # Report archive size
        if archive.file.attached?
          Metrics::Archives::Size.new(
            size_bytes: archive.file.blob.byte_size
          ).call

          # Report compression ratio (estimate original size from JSON)
          # Rough estimate: each point as JSON ~100-200 bytes
          estimated_original_size = actual_count * 150
          Metrics::Archives::CompressionRatio.new(
            original_size: estimated_original_size,
            compressed_size: archive.file.blob.byte_size
          ).call
        end

        archive
      end

      def calculate_checksum(point_ids)
        Digest::SHA256.hexdigest(point_ids.sort.join(','))
      end

      def verify_archive_immediately(archive, expected_point_ids)
        start_time = Time.current

        result = download_and_decrypt_archive(archive, start_time)
        return result unless result[:success]

        result = parse_and_verify_point_ids(result[:content], expected_point_ids, start_time)
        return result unless result[:success]

        Rails.logger.info("✓ Immediate verification passed for archive #{archive.id}")
        report_verification_metric(start_time, 'success')
        { success: true }
      end

      def download_and_decrypt_archive(archive, start_time)
        unless archive.file.attached?
          report_verification_metric(start_time, 'failure', 'file_not_attached')
          return { success: false, error: 'File not attached' }
        end

        encrypted_content = archive.file.blob.download
        if encrypted_content.bytesize.zero?
          report_verification_metric(start_time, 'failure', 'empty_file')
          return { success: false, error: 'File is empty' }
        end

        verify_content_checksum!(encrypted_content, archive.metadata)
        compressed = Encryption.decrypt(encrypted_content)
        { success: true, content: compressed }
      rescue StandardError => e
        report_verification_metric(start_time, 'failure', 'download_or_decrypt_failed')
        { success: false, error: "Download/decrypt failed: #{e.message}" }
      end

      def parse_and_verify_point_ids(compressed_content, expected_point_ids, start_time)
        archived_point_ids = extract_point_ids(compressed_content)

        if archived_point_ids.count != expected_point_ids.count
          report_verification_metric(start_time, 'failure', 'count_mismatch')
          return {
            success: false,
            error: "Point count mismatch: expected #{expected_point_ids.count}, " \
                   "found #{archived_point_ids.count}"
          }
        end

        if calculate_checksum(archived_point_ids) != calculate_checksum(expected_point_ids)
          report_verification_metric(start_time, 'failure', 'checksum_mismatch')
          return { success: false, error: 'Point IDs checksum mismatch in archive' }
        end

        { success: true }
      rescue StandardError => e
        report_verification_metric(start_time, 'failure', 'decompression_failed')
        { success: false, error: "Decompression/parsing failed: #{e.message}" }
      end

      def extract_point_ids(compressed_content)
        io = StringIO.new(compressed_content)
        gz = Zlib::GzipReader.new(io)
        ids = gz.each_line.map { |line| JSON.parse(line)['id'] }
        gz.close
        ids
      end

      def verify_content_checksum!(content, metadata)
        expected = metadata&.dig('content_checksum')
        return if expected.blank?

        actual = Digest::SHA256.hexdigest(content)
        raise 'Content checksum mismatch' unless actual == expected
      end

      def report_verification_metric(start_time, status, check_name = nil)
        duration = Time.current - start_time

        Metrics::Archives::Verification.new(
          duration_seconds: duration,
          status: status,
          check_name: check_name
        ).call
      end
    end
  end
end

# frozen_string_literal: true

module Points
  module RawData
    # Service for archiving raw_data from points.
    #
    # Primary path: ArchiveUserJob calls this per-user with PK cursor (fast).
    # Legacy path: archive_specific_month still works for rake tasks and ReArchiveMonthJob.
    class Archiver
      SAFE_ARCHIVE_LAG = 2.months
      CHUNK_SIZE = 50_000
      FLAG_BATCH_SIZE = 5_000

      def initialize
        @stats = { processed: 0, archived: 0, failed: 0 }
      end

      # Called by ArchiveUserJob — archives all eligible points for a user.
      # Walks forward by PK, never scans the whole table.
      def archive_user(user_id)
        cutoff = SAFE_ARCHIVE_LAG.ago.to_i

        loop do
          point_ids = Point
                      .where(user_id: user_id, raw_data_archived: false)
                      .where('timestamp < ?', cutoff)
                      .where.not(raw_data: [nil, {}])
                      .order(:id)
                      .limit(CHUNK_SIZE)
                      .pluck(:id)

          break if point_ids.empty?

          archive_chunk(user_id, point_ids)
          @stats[:processed] += 1
          @stats[:archived] += point_ids.size
        end

        @stats
      end

      # Legacy: archive a specific month (used by rake tasks and ReArchiveMonthJob).
      def archive_specific_month(user_id, year, month)
        lock_key = "archive_points:#{user_id}:#{year}:#{month}"

        lock_acquired = ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds: 0) do
          point_ids = find_month_point_ids(user_id, year, month)
          next true if point_ids.empty?

          # Process in chunks for large months
          point_ids.each_slice(CHUNK_SIZE) do |chunk_ids|
            archive_chunk(user_id, chunk_ids)
          end
          true
        end

        raise "Could not acquire lock for #{lock_key} — archival already in progress" unless lock_acquired
      end

      private

      def archive_chunk(user_id, point_ids)
        points = Point.where(id: point_ids).select(:id, :raw_data)

        compressed = ChunkCompressor.new(points).compress
        validate_count!(user_id, point_ids, compressed[:count])

        encrypted = Encryption.encrypt(compressed[:data])

        first_ts = Point.where(id: point_ids.first).pick(:timestamp)
        time = Time.at(first_ts).utc

        archive = nil
        ActiveRecord::Base.transaction do
          archive = create_archive_record(user_id, time, point_ids, encrypted, compressed)
        end

        # Full verification OUTSIDE transaction to avoid holding DB connection during I/O.
        # Downloads the archive, decrypts, decompresses, and verifies point count + checksum.
        verify_archive_full!(archive, point_ids)

        # Only flag points after verification succeeds
        flag_points_batched(point_ids, archive.id)

        report_metrics(archive, point_ids.size, compressed)

        Rails.logger.info(
          "Archived chunk #{archive.id}: #{point_ids.size} points " \
          "(IDs #{point_ids.first}..#{point_ids.last})"
        )
      end

      def find_month_point_ids(user_id, year, month)
        start_of_month = Time.utc(year, month, 1).to_i
        end_of_month = (Time.utc(year, month, 1) + 1.month).to_i

        Point.where(user_id: user_id, raw_data_archived: false)
             .where(timestamp: start_of_month...end_of_month)
             .where.not(raw_data: [nil, {}])
             .order(:id)
             .pluck(:id)
      end

      def validate_count!(user_id, point_ids, actual_count)
        expected_count = point_ids.size
        return if actual_count == expected_count

        first_ts = Point.where(id: point_ids.first).pick(:timestamp)
        time = first_ts ? Time.at(first_ts).utc : Time.current.utc

        Metrics::Archives::CountMismatch.new(
          user_id: user_id,
          year: time.year,
          month: time.month,
          expected: expected_count,
          actual: actual_count
        ).call

        error_msg = "Archive count mismatch for user #{user_id}: " \
                    "expected #{expected_count}, got #{actual_count}"
        Rails.logger.error(error_msg)
        ExceptionReporter.call(StandardError.new(error_msg), error_msg)
        raise StandardError, error_msg
      end

      # Full round-trip verification: download → decrypt → decompress → parse → count + checksum.
      # Runs OUTSIDE the transaction so network I/O doesn't hold DB connections.
      # On failure, destroys the archive record and raises to prevent flagging points.
      def verify_archive_full!(archive, point_ids)
        raise StandardError, "Archive #{archive.id} has no attached file" unless archive.file.attached?

        raw_content = archive.file.download
        raise StandardError, "Archive #{archive.id} has zero-byte file" if raw_content.bytesize.zero?

        # Verify content checksum (catches storage-layer corruption)
        stored_checksum = archive.metadata&.dig('content_checksum')
        if stored_checksum.present?
          actual_checksum = Digest::SHA256.hexdigest(raw_content)
          if actual_checksum != stored_checksum
            cleanup_failed_archive!(archive)
            raise StandardError,
                  "Archive #{archive.id} content checksum mismatch"
          end
        end

        # Decrypt and decompress to verify data integrity
        decrypted = Encryption.decrypt_if_needed(raw_content, archive)
        io = StringIO.new(decrypted)
        gz = Zlib::GzipReader.new(io)
        verified_ids = []
        gz.each_line do |line|
          data = JSON.parse(line)
          verified_ids << data['id']
        end
        gz.close

        # Verify point count matches
        if verified_ids.size != point_ids.size
          cleanup_failed_archive!(archive)
          raise StandardError,
                "Archive #{archive.id} point count mismatch: " \
                "expected #{point_ids.size}, got #{verified_ids.size}"
        end

        # Verify point IDs checksum matches
        verified_checksum = Digest::SHA256.hexdigest(verified_ids.sort.join(','))
        expected_checksum = archive.point_ids_checksum
        return if verified_checksum == expected_checksum

        cleanup_failed_archive!(archive)
        raise StandardError,
              "Archive #{archive.id} point IDs checksum mismatch"
      rescue Zlib::GzipFile::Error, JSON::ParserError, OpenSSL::Cipher::CipherError => e
        cleanup_failed_archive!(archive)
        raise StandardError,
              "Archive #{archive.id} decrypt/decompress failed: #{e.message}"
      end

      def cleanup_failed_archive!(archive)
        archive.file.purge if archive.file.attached?
        archive.destroy!
      rescue StandardError => e
        Rails.logger.error("Failed to clean up archive #{archive.id}: #{e.message}")
      end

      def flag_points_batched(point_ids, archive_id)
        point_ids.each_slice(FLAG_BATCH_SIZE) do |batch|
          Point.where(id: batch).update_all(
            raw_data_archived: true,
            raw_data_archive_id: archive_id
          )
        end
      end

      def create_archive_record(user_id, time, point_ids, encrypted, compressed)
        chunk_number = Points::RawDataArchive
                       .where(user_id: user_id, year: time.year, month: time.month)
                       .maximum(:chunk_number).to_i + 1

        chunk_filename = "#{format('%03d', chunk_number)}.jsonl.gz.enc"

        archive = Points::RawDataArchive.create!(
          user_id: user_id,
          year: time.year,
          month: time.month,
          chunk_number: chunk_number,
          point_count: point_ids.size,
          point_ids_checksum: Digest::SHA256.hexdigest(point_ids.sort.join(',')),
          archived_at: Time.current,
          metadata: {
            format_version: 2,
            compression: 'gzip',
            encryption: 'aes-256-gcm',
            content_checksum: Digest::SHA256.hexdigest(encrypted),
            min_point_id: point_ids.first,
            max_point_id: point_ids.last,
            expected_count: point_ids.size,
            actual_count: compressed[:count]
          }
        )

        storage_key = "raw_data_archives/#{user_id}/#{time.year}/" \
                      "#{format('%02d', time.month)}/#{chunk_filename}"

        archive.file.attach(
          io: StringIO.new(encrypted),
          filename: chunk_filename,
          content_type: 'application/octet-stream',
          key: storage_key
        )

        archive
      end

      def report_metrics(archive, count, compressed)
        Metrics::Archives::Operation.new(operation: 'archive', status: 'success').call
        Metrics::Archives::PointsArchived.new(count: count, operation: 'added').call

        return unless archive.file.attached?

        Metrics::Archives::Size.new(size_bytes: archive.file.blob.byte_size).call
        Metrics::Archives::CompressionRatio.new(
          original_size: compressed[:uncompressed_size],
          compressed_size: archive.file.blob.byte_size
        ).call
      end
    end
  end
end

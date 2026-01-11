# frozen_string_literal: true

module Points
  module RawData
    class Verifier
      def initialize
        @stats = { verified: 0, failed: 0 }
      end

      def call
        Rails.logger.info('Starting raw_data archive verification...')

        unverified_archives.find_each do |archive|
          verify_archive(archive)
        end

        Rails.logger.info("Verification complete: #{@stats}")
        @stats
      end

      def verify_specific_archive(archive_id)
        archive = Points::RawDataArchive.find(archive_id)
        verify_archive(archive)
      end

      def verify_month(user_id, year, month)
        archives = Points::RawDataArchive.for_month(user_id, year, month)
                                         .where(verified_at: nil)

        Rails.logger.info("Verifying #{archives.count} archives for #{year}-#{format('%02d', month)}...")

        archives.each { |archive| verify_archive(archive) }
      end

      private

      def unverified_archives
        Points::RawDataArchive.where(verified_at: nil)
      end

      def verify_archive(archive)
        Rails.logger.info("Verifying archive #{archive.id} (#{archive.month_display}, chunk #{archive.chunk_number})...")
        start_time = Time.current

        verification_result = perform_verification(archive)

        if verification_result[:success]
          archive.update!(verified_at: Time.current)
          @stats[:verified] += 1
          Rails.logger.info("✓ Archive #{archive.id} verified successfully")

          Metrics::Archives::Operation.new(
            operation: 'verify',
            status: 'success'
          ).call

          report_verification_metric(start_time, 'success')
        else
          @stats[:failed] += 1
          Rails.logger.error("✗ Archive #{archive.id} verification failed: #{verification_result[:error]}")
          ExceptionReporter.call(
            StandardError.new(verification_result[:error]),
            "Archive verification failed for archive #{archive.id}"
          )

          Metrics::Archives::Operation.new(
            operation: 'verify',
            status: 'failure'
          ).call

          check_name = extract_check_name_from_error(verification_result[:error])
          report_verification_metric(start_time, 'failure', check_name)
        end
      rescue StandardError => e
        @stats[:failed] += 1
        ExceptionReporter.call(e, "Failed to verify archive #{archive.id}")
        Rails.logger.error("✗ Archive #{archive.id} verification error: #{e.message}")

        Metrics::Archives::Operation.new(
          operation: 'verify',
          status: 'failure'
        ).call

        report_verification_metric(start_time, 'failure', 'exception')
      end

      def perform_verification(archive)
        return { success: false, error: 'File not attached' } unless archive.file.attached?

        begin
          compressed_content = archive.file.blob.download
        rescue StandardError => e
          return { success: false, error: "File download failed: #{e.message}" }
        end

        return { success: false, error: 'File is empty' } if compressed_content.bytesize.zero?

        if archive.file.blob.checksum.present?
          calculated_checksum = Digest::MD5.base64digest(compressed_content)
          return { success: false, error: 'MD5 checksum mismatch' } if calculated_checksum != archive.file.blob.checksum
        end

        begin
          archived_data = decompress_and_extract_data(compressed_content)
        rescue StandardError => e
          return { success: false, error: "Decompression/parsing failed: #{e.message}" }
        end

        point_ids = archived_data.keys

        if point_ids.count != archive.point_count
          return {
            success: false,
            error: "Point count mismatch: expected #{archive.point_count}, found #{point_ids.count}"
          }
        end

        calculated_checksum = calculate_checksum(point_ids)
        if calculated_checksum != archive.point_ids_checksum
          return { success: false, error: 'Point IDs checksum mismatch' }
        end

        existing_count = Point.where(id: point_ids).count
        if existing_count != point_ids.count
          Rails.logger.info(
            "Archive #{archive.id}: #{point_ids.count - existing_count} points no longer in database " \
            "(#{existing_count}/#{point_ids.count} remaining). This is OK if user deleted their data."
          )
        end

        if existing_count.positive?
          verification_result = verify_raw_data_matches(archived_data)
          return verification_result unless verification_result[:success]
        else
          Rails.logger.info(
            "Archive #{archive.id}: Skipping raw_data verification - no points remain in database"
          )
        end

        { success: true }
      end

      def decompress_and_extract_data(compressed_content)
        io = StringIO.new(compressed_content)
        gz = Zlib::GzipReader.new(io)
        archived_data = {}

        gz.each_line do |line|
          data = JSON.parse(line)
          archived_data[data['id']] = data['raw_data']
        end

        gz.close
        archived_data
      end

      def verify_raw_data_matches(archived_data)
        # For small archives, verify all points. For large archives, sample up to 100 points.
        # Always verify all if 100 or fewer points for maximum accuracy
        point_ids_to_check = if archived_data.size <= 100
                               archived_data.keys
                             else
                               archived_data.keys.sample(100)
                             end

        # Filter to only check points that still exist in the database
        existing_point_ids = Point.where(id: point_ids_to_check).pluck(:id)

        if existing_point_ids.empty?
          Rails.logger.info('No points remaining to verify raw_data matches')
          return { success: true }
        end

        mismatches = []

        Point.where(id: existing_point_ids).find_each do |point|
          archived_raw_data = archived_data[point.id]
          current_raw_data = point.raw_data

          # Compare the raw_data (both should be hashes)
          if archived_raw_data != current_raw_data
            mismatches << {
              point_id: point.id,
              archived: archived_raw_data,
              current: current_raw_data
            }
          end
        end

        if mismatches.any?
          return {
            success: false,
            error: "Raw data mismatch detected in #{mismatches.count} point(s). " \
                   "First mismatch: Point #{mismatches.first[:point_id]}"
          }
        end

        { success: true }
      end

      def calculate_checksum(point_ids)
        Digest::SHA256.hexdigest(point_ids.sort.join(','))
      end

      def report_verification_metric(start_time, status, check_name = nil)
        duration = Time.current - start_time

        Metrics::Archives::Verification.new(
          duration_seconds: duration,
          status: status,
          check_name: check_name
        ).call
      end

      def extract_check_name_from_error(error_message)
        case error_message
        when /File not attached/i
          'file_not_attached'
        when /File download failed/i
          'download_failed'
        when /File is empty/i
          'empty_file'
        when /MD5 checksum mismatch/i
          'md5_checksum_mismatch'
        when %r{Decompression/parsing failed}i
          'decompression_failed'
        when /Point count mismatch/i
          'count_mismatch'
        when /Point IDs checksum mismatch/i
          'checksum_mismatch'
        when /Raw data mismatch/i
          'raw_data_mismatch'
        else
          'unknown'
        end
      end
    end
  end
end

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
        msg = "Verifying archive #{archive.id} (#{archive.month_display}, chunk #{archive.chunk_number})..."
        Rails.logger.info(msg)
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
        result = download_and_verify_content(archive)
        return result unless result[:success]

        compressed_content = result[:compressed_content]
        result = parse_and_verify_points(archive, compressed_content)
        return result unless result[:success]

        verify_existing_points(archive, result[:point_ids], result[:sampled_data])
      end

      def download_and_verify_content(archive)
        return { success: false, error: 'File not attached' } unless archive.file.attached?

        raw_content = archive.file.blob.download
        return { success: false, error: 'File is empty' } if raw_content.bytesize.zero?

        verify_content_integrity(raw_content, archive)
      rescue StandardError => e
        { success: false, error: "File download failed: #{e.message}" }
      end

      def verify_content_integrity(raw_content, archive)
        stored_checksum = archive.metadata&.dig('content_checksum')
        if stored_checksum.present?
          actual_checksum = Digest::SHA256.hexdigest(raw_content)
          return { success: false, error: 'Content checksum mismatch' } if actual_checksum != stored_checksum
        end

        compressed_content = Encryption.decrypt_if_needed(raw_content, archive)
        { success: true, compressed_content: compressed_content }
      end

      def parse_and_verify_points(archive, compressed_content)
        parse_result = stream_parse_archive(compressed_content, archive.point_count)
        point_ids = parse_result[:point_ids]

        if point_ids.count != archive.point_count
          return {
            success: false,
            error: "Point count mismatch: expected #{archive.point_count}, found #{point_ids.count}"
          }
        end

        id_checksum = calculate_checksum(point_ids)
        return { success: false, error: 'Point IDs checksum mismatch' } if id_checksum != archive.point_ids_checksum

        { success: true, point_ids: point_ids, sampled_data: parse_result[:sampled_data] }
      rescue StandardError => e
        { success: false, error: "Decompression/parsing failed: #{e.message}" }
      end

      def verify_existing_points(archive, point_ids, sampled_data)
        existing_count = Point.where(id: point_ids).count
        if existing_count != point_ids.count
          Rails.logger.info(
            "Archive #{archive.id}: #{point_ids.count - existing_count} points no longer in database " \
            "(#{existing_count}/#{point_ids.count} remaining). This is OK if user deleted their data."
          )
        end

        if existing_count.positive?
          verification_result = verify_raw_data_matches(sampled_data)
          return verification_result unless verification_result[:success]
        else
          Rails.logger.info(
            "Archive #{archive.id}: Skipping raw_data verification - no points remain in database"
          )
        end

        { success: true }
      end

      # Stream-parse the archive in a single pass. Collects all point IDs (integers only)
      # and raw_data only for deterministically sampled indices. This avoids loading the
      # full raw_data hash into memory (which would ~3x the memory footprint).
      def stream_parse_archive(compressed_content, expected_count)
        sample_indices = build_sample_indices(expected_count)

        io = StringIO.new(compressed_content)
        gz = Zlib::GzipReader.new(io)

        point_ids = []
        sampled_data = {} # Only populated for sampled indices
        line_index = 0

        gz.each_line do |line|
          data = JSON.parse(line)
          point_id = data['id']
          point_ids << point_id

          sampled_data[point_id] = data['raw_data'] if sample_indices.include?(line_index)

          line_index += 1
        end

        gz.close
        { point_ids: point_ids, sampled_data: sampled_data }
      end

      # Deterministic stride-based sampling. Sample size scales with archive size:
      # sqrt(n) points, clamped to [min 100, max 1000]. Uses evenly spaced indices
      # so the sample covers the full range of the archive (head, middle, tail),
      # catching systematic corruption like truncated gzip streams.
      def build_sample_indices(total_count)
        return (0...total_count).to_set if total_count <= 100

        sample_size = [[Math.sqrt(total_count).ceil, 100].max, 1000].min
        stride = total_count.to_f / sample_size

        (0...sample_size).map { |i| (i * stride).floor }.to_set
      end

      def verify_raw_data_matches(sampled_data)
        existing_point_ids = Point.where(id: sampled_data.keys).pluck(:id)

        if existing_point_ids.empty?
          Rails.logger.info('No sampled points remaining to verify raw_data matches')
          return { success: true }
        end

        mismatches = []

        Point.where(id: existing_point_ids).find_each do |point|
          archived_raw_data = sampled_data[point.id]
          next if archived_raw_data.nil?

          mismatches << { point_id: point.id } if archived_raw_data != point.raw_data
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
        when /Content checksum mismatch/i
          'content_checksum_mismatch'
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

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

        verification_result = perform_verification(archive)

        if verification_result[:success]
          archive.update!(verified_at: Time.current)
          @stats[:verified] += 1
          Rails.logger.info("✓ Archive #{archive.id} verified successfully")
        else
          @stats[:failed] += 1
          Rails.logger.error("✗ Archive #{archive.id} verification failed: #{verification_result[:error]}")
          ExceptionReporter.call(
            StandardError.new(verification_result[:error]),
            "Archive verification failed for archive #{archive.id}"
          )
        end
      rescue StandardError => e
        @stats[:failed] += 1
        ExceptionReporter.call(e, "Failed to verify archive #{archive.id}")
        Rails.logger.error("✗ Archive #{archive.id} verification error: #{e.message}")
      end

      def perform_verification(archive)
        # 1. Verify file exists and is attached
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

        # 4. Verify MD5 checksum (if blob has checksum)
        if archive.file.blob.checksum.present?
          calculated_checksum = Digest::MD5.base64digest(compressed_content)
          if calculated_checksum != archive.file.blob.checksum
            return { success: false, error: 'MD5 checksum mismatch' }
          end
        end

        # 5. Verify file can be decompressed and is valid JSONL
        begin
          point_ids = decompress_and_extract_point_ids(compressed_content)
        rescue StandardError => e
          return { success: false, error: "Decompression/parsing failed: #{e.message}" }
        end

        # 6. Verify point count matches
        if point_ids.count != archive.point_count
          return {
            success: false,
            error: "Point count mismatch: expected #{archive.point_count}, found #{point_ids.count}"
          }
        end

        # 7. Verify point IDs checksum matches
        calculated_checksum = calculate_checksum(point_ids)
        if calculated_checksum != archive.point_ids_checksum
          return { success: false, error: 'Point IDs checksum mismatch' }
        end

        # 8. Verify all points still exist in database
        existing_count = Point.where(id: point_ids).count
        if existing_count != point_ids.count
          return {
            success: false,
            error: "Missing points in database: expected #{point_ids.count}, found #{existing_count}"
          }
        end

        { success: true }
      end

      def decompress_and_extract_point_ids(compressed_content)
        io = StringIO.new(compressed_content)
        gz = Zlib::GzipReader.new(io)
        point_ids = []

        gz.each_line do |line|
          data = JSON.parse(line)
          point_ids << data['id']
        end

        gz.close
        point_ids
      end

      def calculate_checksum(point_ids)
        Digest::SHA256.hexdigest(point_ids.sort.join(','))
      end
    end
  end
end

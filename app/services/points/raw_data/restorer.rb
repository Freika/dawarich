# frozen_string_literal: true

module Points
  module RawData
    class Restorer
      def restore_to_database(user_id, year, month)
        archives = Points::RawDataArchive.for_month(user_id, year, month)

        raise "No archives found for user #{user_id}, #{year}-#{month}" if archives.empty?

        Rails.logger.info("Restoring #{archives.count} archives to database...")
        total_points = archives.sum(:point_count)

        begin
          Point.transaction do
            archives.each { restore_archive_to_db(_1) }
          end

          Rails.logger.info("✓ Restored #{total_points} points")

          # Report successful restore operation
          Metrics::Archives::Operation.new(
            operation: 'restore',
            status: 'success'
          ).call

          # Report points restored (removed from archived state)
          Metrics::Archives::PointsArchived.new(
            count: total_points,
            operation: 'removed'
          ).call
        rescue StandardError => e
          # Report failed restore operation
          Metrics::Archives::Operation.new(
            operation: 'restore',
            status: 'failure'
          ).call

          raise
        end
      end

      def restore_to_memory(user_id, year, month)
        archives = Points::RawDataArchive.for_month(user_id, year, month)

        raise "No archives found for user #{user_id}, #{year}-#{month}" if archives.empty?

        Rails.logger.info("Loading #{archives.count} archives into cache...")

        cache_key_prefix = "raw_data:temp:#{user_id}:#{year}:#{month}"
        count = 0

        archives.each do |archive|
          count += restore_archive_to_cache(archive, cache_key_prefix)
        end

        Rails.logger.info("✓ Loaded #{count} points into cache (expires in 1 hour)")
      end

      def restore_all_for_user(user_id)
        archives =
          Points::RawDataArchive.where(user_id: user_id)
                                .select(:year, :month)
                                .distinct
                                .order(:year, :month)

        Rails.logger.info("Restoring #{archives.count} months for user #{user_id}...")

        archives.each do |archive|
          restore_to_database(user_id, archive.year, archive.month)
        end

        Rails.logger.info('✓ Complete user restore finished')
      end

      private

      def restore_archive_to_db(archive)
        decompressed = download_and_decompress(archive)

        decompressed.each_line do |line|
          data = JSON.parse(line)

          Point.where(id: data['id']).update_all(
            raw_data: data['raw_data'],
            raw_data_archived: false,
            raw_data_archive_id: nil
          )
        end
      end

      def restore_archive_to_cache(archive, cache_key_prefix)
        decompressed = download_and_decompress(archive)
        count = 0

        decompressed.each_line do |line|
          data = JSON.parse(line)

          Rails.cache.write(
            "#{cache_key_prefix}:#{data['id']}",
            data['raw_data'],
            expires_in: 1.hour
          )

          count += 1
        end

        count
      end

      def download_and_decompress(archive)
        # Download via ActiveStorage
        compressed_content = archive.file.blob.download

        # Decompress
        io = StringIO.new(compressed_content)
        gz = Zlib::GzipReader.new(io)
        content = gz.read
        gz.close

        content
      rescue StandardError => e
        Rails.logger.error("Failed to download/decompress archive #{archive.id}: #{e.message}")
        raise
      end
    end
  end
end

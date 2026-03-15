# frozen_string_literal: true

module Points
  module RawData
    class Restorer
      BATCH_SIZE = 1000

      def restore_to_database(user_id, year, month)
        archives = Points::RawDataArchive.for_month(user_id, year, month)

        raise "No archives found for user #{user_id}, #{year}-#{month}" if archives.empty?

        Rails.logger.info("Restoring #{archives.count} archives to database...")

        total_restored = 0
        total_missing = 0

        begin
          Point.transaction do
            archives.each do |archive|
              result = restore_archive_to_db(archive)
              total_restored += result[:restored]
              total_missing += result[:missing]
            end
          end

          Rails.logger.info("✓ Restored #{total_restored} points")

          if total_missing.positive?
            Rails.logger.warn(
              "⚠ #{total_missing} archived points no longer exist in database " \
              "for user #{user_id}, #{year}-#{month}. Their raw_data cannot be restored."
            )
          end

          Metrics::Archives::Operation.new(
            operation: 'restore',
            status: 'success'
          ).call

          Metrics::Archives::PointsArchived.new(
            count: total_restored,
            operation: 'removed'
          ).call
        rescue StandardError
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
        archived_data = parse_archived_data(decompressed)

        total_restored = 0
        total_missing = 0

        archived_data.each_slice(BATCH_SIZE) do |batch|
          result = restore_batch(batch)
          total_restored += result[:restored]
          total_missing += result[:missing]
        end

        { restored: total_restored, missing: total_missing }
      end

      def parse_archived_data(decompressed)
        decompressed.each_line.map do |line|
          data = JSON.parse(line)
          [data['id'], data['raw_data']]
        end
      end

      def restore_batch(batch)
        point_ids = batch.map(&:first)
        existing_ids = Point.where(id: point_ids).pluck(:id).to_set

        missing_ids = point_ids.reject { |id| existing_ids.include?(id) }
        if missing_ids.any?
          Rails.logger.warn(
            "Points no longer in database (skipping restore): #{missing_ids.join(', ')}"
          )
        end

        restorable = batch.select { |id, _| existing_ids.include?(id) }
        batch_update_points(restorable) if restorable.any?

        { restored: restorable.size, missing: missing_ids.size }
      end

      def batch_update_points(entries)
        updates = entries.map do |id, raw_data|
          { id: id, raw_data: raw_data, raw_data_archived: false, raw_data_archive_id: nil }
        end

        Point.upsert_all(updates, unique_by: :id,
                          update_only: %i[raw_data raw_data_archived raw_data_archive_id])
        # rubocop:enable Rails/SkipsModelValidations
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
        raw_content = archive.file.blob.download

        compressed_content = Encryption.decrypt_if_needed(raw_content, archive)

        io = StringIO.new(compressed_content)
        gz = Zlib::GzipReader.new(io)
        content = gz.read
        gz.close

        content
      rescue StandardError => e
        Rails.logger.error("Failed to download/decrypt/decompress archive #{archive.id}: #{e.message}")
        raise
      end
    end
  end
end

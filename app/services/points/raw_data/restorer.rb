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
        total_skipped = 0

        begin
          archives.each do |archive|
            result = restore_archive_to_db(archive)
            total_restored += result[:restored]
            total_missing += result[:missing]
            total_skipped += result[:skipped]
          end

          Rails.logger.info("✓ Restored #{total_restored} points")

          if total_missing.positive?
            Rails.logger.warn(
              "⚠ #{total_missing} archived points no longer exist in database " \
              "for user #{user_id}, #{year}-#{month}. Their raw_data cannot be restored."
            )
          end

          if total_skipped.positive?
            Rails.logger.warn(
              "Skipped #{total_skipped} point snapshots no longer linked to their source archive"
            )
          end

          Yabeda.dawarich_archive.operations_total.increment({ operation: 'restore', status: 'success' })
          Yabeda.dawarich_archive.points_total.increment({ operation: 'restored' }, by: total_restored)
        rescue StandardError
          Yabeda.dawarich_archive.operations_total.increment({ operation: 'restore', status: 'failure' })

          raise
        end
      end

      def restore_to_memory(user_id, year, month)
        archives = Points::RawDataArchive.for_month(user_id, year, month)

        raise "No archives found for user #{user_id}, #{year}-#{month}" if archives.empty?

        Rails.logger.info("Loading #{archives.count} archives into cache...")

        cache_key_prefix = "raw_data:temp:#{user_id}"
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

      # Each archive batch commits independently so row locks stay bounded.
      # If a later batch fails, a retry resumes from the still-linked points;
      # completed batches are already safely detached from their archive.
      def restore_archive_to_db(archive)
        decompressed = download_and_decompress(archive)
        archived_data = parse_archived_data(decompressed)

        total_restored = 0
        total_missing = 0
        total_skipped = 0

        archived_data.each_slice(BATCH_SIZE) do |batch|
          result = restore_batch(batch, archive.id)
          total_restored += result[:restored]
          total_missing += result[:missing]
          total_skipped += result[:skipped]
        end

        { restored: total_restored, missing: total_missing, skipped: total_skipped }
      end

      def parse_archived_data(decompressed)
        decompressed.each_line.map do |line|
          data = JSON.parse(line)
          [data['id'], data['raw_data']]
        end
      end

      def restore_batch(batch, archive_id)
        Point.with_write_contention_retry do
          Point.transaction do
            point_ids = batch.map(&:first)
            existing_ids = Point.where(id: point_ids).pluck(:id).to_set
            linked_ids = Point.raw_data_lock_order.where(
              id: point_ids,
              raw_data_archived: true,
              raw_data_archive_id: archive_id
            ).lock.pluck(:id)

            missing_ids = point_ids.reject { |id| existing_ids.include?(id) }
            if missing_ids.any?
              Rails.logger.warn(
                "Points no longer in database (skipping restore): #{missing_ids.join(', ')}"
              )
            end

            data_by_id = batch.to_h
            restorable = linked_ids.filter_map { |id| [id, data_by_id[id]] if data_by_id.key?(id) }
            batch_update_points(restorable) if restorable.any?

            {
              restored: restorable.size,
              missing: missing_ids.size,
              skipped: (existing_ids - linked_ids.to_set).size
            }
          end
        end
      end

      # A real UPDATE, not upsert_all: Postgres checks NOT NULL on the
      # proposed insert tuple BEFORE resolving the conflict, so a partial
      # upsert dies on v2's `timestamp NOT NULL` - and an id that no longer
      # exists must not resurrect as a hollow point anyway.
      def batch_update_points(entries)
        connection = ActiveRecord::Base.connection
        values = entries.map do |id, raw_data|
          "(#{id.to_i}, #{connection.quote(raw_data.to_json)}::jsonb)"
        end

        connection.execute(<<~SQL)
          UPDATE points
          SET raw_data = v.raw_data,
              raw_data_archived = false,
              raw_data_archive_id = NULL
          FROM (VALUES #{values.join(', ')}) AS v(id, raw_data)
          WHERE points.id = v.id
        SQL
      end

      def restore_archive_to_cache(archive, cache_key_prefix)
        decompressed = download_and_decompress(archive)
        linked_ids = Point.where(raw_data_archived: true, raw_data_archive_id: archive.id).pluck(:id).to_set
        count = 0

        decompressed.each_line do |line|
          data = JSON.parse(line)
          id = data['id']
          next unless linked_ids.include?(id)

          Rails.cache.write(
            "#{cache_key_prefix}:#{id}:#{archive.id}",
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

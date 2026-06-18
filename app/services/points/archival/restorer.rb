# frozen_string_literal: true

module Points
  module Archival
    class Restorer
      BATCH_SIZE = 5_000

      def restore_user(user_id)
        archives = Points::Archive.where(user_id:).where.not(verified_at: nil).order(:year, :month, :chunk_number)
        @valid_visit_ids = Visit.where(user_id:).pluck(:id).to_set
        @valid_raw_data_archive_ids = Points::RawDataArchive.where(user_id:).pluck(:id).to_set
        purgeable = archives.select { |archive| restore_archive(archive) }
        recompute_counters(user_id)
        purgeable.each { |archive| purge(archive) }
      end

      private

      def restore_archive(archive)
        raw = archive.file.download
        decrypted = Points::RawData::Encryption.decrypt_if_needed(raw, archive)

        ids = []
        rows = []
        Zlib::GzipReader.new(StringIO.new(decrypted)).each_line do |line|
          row = sanitize_foreign_keys(Serializer.parse(line))
          ids << row['id']
          rows << row
          flush(rows) if rows.size >= BATCH_SIZE
        end
        flush(rows)
        fully_restored?(archive, ids)
      end

      def fully_restored?(archive, ids)
        present = Point.where(id: ids).count
        return true if present == ids.size

        Rails.logger.warn(
          "[points_archival] archive #{archive.id} not fully restored (#{present}/#{ids.size}); keeping it"
        )
        false
      end

      def sanitize_foreign_keys(row)
        row['visit_id'] = nil if row['visit_id'] && @valid_visit_ids.exclude?(row['visit_id'])
        if row['raw_data_archive_id'] && @valid_raw_data_archive_ids.exclude?(row['raw_data_archive_id'])
          row['raw_data_archive_id'] = nil
        end
        row
      end

      def flush(rows)
        return if rows.empty?

        Point.connection.execute(Serializer.insert_sql(rows))
        rows.clear
      end

      def recompute_counters(user_id)
        actual = Point.where(user_id:).count
        User.where(id: user_id).update_all(points_count: actual)

        per_import = Point.where(user_id:).group(:import_id).count
        Import.where(user_id:).find_each do |import|
          import.update_column(:points_count, per_import[import.id].to_i)
        end
      end

      def purge(archive)
        archive.file.purge if archive.file.attached?
        archive.destroy!
      end
    end
  end
end

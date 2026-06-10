# frozen_string_literal: true

module Points
  module Archival
    class Restorer
      BATCH_SIZE = 5_000

      def restore_user(user_id)
        archives = Points::Archive.where(user_id:).where.not(verified_at: nil).order(:year, :month, :chunk_number)
        archives.each { |archive| restore_archive(archive) }
        recompute_counters(user_id)
        archives.each { |archive| purge(archive) }
      end

      private

      def restore_archive(archive)
        raw = archive.file.download
        decrypted = Points::RawData::Encryption.decrypt_if_needed(raw, archive)

        rows = []
        Zlib::GzipReader.new(StringIO.new(decrypted)).each_line do |line|
          rows << Serializer.parse(line)
          flush(rows) if rows.size >= BATCH_SIZE
        end
        flush(rows)
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

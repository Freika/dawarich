# frozen_string_literal: true

module Points
  module Archival
    class Archiver
      CHUNK_SIZE = 50_000

      def archive_user(user_id)
        months(user_id).each do |year, month|
          archive_month(user_id, year, month)
        end
      end

      private

      def months(user_id)
        Point.where(user_id:)
             .pluck(Arel.sql("DISTINCT EXTRACT(YEAR FROM to_timestamp(timestamp) AT TIME ZONE 'UTC')::int, " \
                             "EXTRACT(MONTH FROM to_timestamp(timestamp) AT TIME ZONE 'UTC')::int"))
      end

      def archive_month(user_id, year, month)
        start_ts = Time.utc(year, month, 1).to_i
        end_ts = (Time.utc(year, month, 1) + 1.month).to_i

        point_ids = Point.where(user_id:, timestamp: start_ts...end_ts).order(:id).pluck(:id)
        return if point_ids.empty?

        point_ids.each_slice(CHUNK_SIZE) do |chunk_ids|
          archive_chunk(user_id, year, month, chunk_ids)
        end
      end

      def archive_chunk(user_id, year, month, point_ids)
        compressed = RowCompressor.new(Point.where(id: point_ids)).compress
        encrypted = Points::RawData::Encryption.encrypt(compressed[:data])

        archive = create_record(user_id, year, month, point_ids, encrypted)
        verify!(archive, point_ids)
        archive.update!(verified_at: Time.current)
      end

      def create_record(user_id, year, month, point_ids, encrypted)
        chunk_number = Points::Archive.where(user_id:, year:, month:).maximum(:chunk_number).to_i + 1
        archive = Points::Archive.create!(
          user_id:, year:, month:, chunk_number:,
          point_count: point_ids.size,
          point_ids_checksum: checksum(point_ids),
          archived_at: Time.current,
          metadata: {
            format_version: 2, compression: 'gzip', encryption: 'aes-256-gcm',
            content_checksum: Digest::SHA256.hexdigest(encrypted),
            min_point_id: point_ids.first, max_point_id: point_ids.last
          }
        )
        archive.file.attach(
          io: StringIO.new(encrypted), filename: File.basename(archive.storage_key),
          content_type: 'application/octet-stream', key: archive.storage_key
        )
        archive
      end

      def verify!(archive, point_ids)
        raw = archive.file.download
        stored = archive.metadata['content_checksum']
        raise "checksum mismatch for archive #{archive.id}" if Digest::SHA256.hexdigest(raw) != stored

        decrypted = Points::RawData::Encryption.decrypt_if_needed(raw, archive)
        ids = []
        Zlib::GzipReader.new(StringIO.new(decrypted)).each_line { |l| ids << JSON.parse(l)['id'] }

        raise "count mismatch for archive #{archive.id}" if ids.size != point_ids.size
        raise "id checksum mismatch for archive #{archive.id}" if checksum(ids) != archive.point_ids_checksum
      rescue StandardError
        archive.file.purge if archive.file.attached?
        archive.destroy!
        raise
      end

      def checksum(ids)
        Digest::SHA256.hexdigest(ids.sort.join(','))
      end
    end
  end
end

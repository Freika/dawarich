# frozen_string_literal: true

module Points
  module Archival
    class DeleteSweepJob < ApplicationJob
      queue_as :archival

      def perform
        delay_days = ENV.fetch('POINTS_ARCHIVAL_DELETE_DELAY_DAYS', 7).to_i
        Points::Archive.deletable(delay_days.days.ago).find_each do |archive|
          ids = verified_point_ids(archive)
          next if ids.nil?

          delete_rows(archive.user_id, ids)
          archive.update!(deleted_at: Time.current)
          reset_counters(archive.user_id)
        end
      end

      private

      # Re-verify the S3 object downloads AND its content checksum matches,
      # then return the exact point ids the archive contains. Returns nil if
      # the archive cannot be re-verified (so callers must skip deletion).
      def verified_point_ids(archive)
        return nil unless archive.file.attached?

        raw = archive.file.download
        return nil if Digest::SHA256.hexdigest(raw) != archive.metadata['content_checksum']

        decrypted = Points::RawData::Encryption.decrypt_if_needed(raw, archive)
        ids = []
        Zlib::GzipReader.new(StringIO.new(decrypted)).each_line { |l| ids << JSON.parse(l)['id'] }
        ids
      rescue StandardError
        nil
      end

      def delete_rows(user_id, ids)
        ids.each_slice(10_000) do |slice|
          Point.where(user_id:, id: slice).delete_all
        end
      end

      def reset_counters(user_id)
        User.where(id: user_id).update_all(points_count: Point.where(user_id:).count)
        Import.where(user_id:).find_each do |import|
          import.update_column(:points_count, Point.where(import_id: import.id).count)
        end
      end
    end
  end
end

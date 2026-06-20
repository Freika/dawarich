# frozen_string_literal: true

module Points
  module Archival
    class DeleteSweepJob < ApplicationJob
      queue_as :archival

      def perform
        return unless Flipper.enabled?(:points_archival)

        delay_days = ENV.fetch('POINTS_ARCHIVAL_DELETE_DELAY_DAYS', 7).to_i
        before = delay_days.days.ago
        user_ids = Points::Archive.deletable(before).distinct.pluck(:user_id)

        user_ids.each { |user_id| sweep_user(user_id, before) }
      end

      private

      def sweep_user(user_id, before)
        return unless archived?(user_id)

        Points::Archive.deletable(before).where(user_id:).find_each do |archive|
          ids = verified_point_ids(archive)
          next if ids.nil?

          delete_archive(user_id, archive, ids)
        end
        reset_counters(user_id)
      end

      # Delete the archived points under a transaction-scoped advisory lock, after
      # re-confirming the user is still archived. A returning user is flipped to
      # :restoring under the same lock, so this never deletes rows out from under
      # an in-flight restore. The slow S3 re-verify stays outside the lock.
      def delete_archive(user_id, archive, ids)
        Points::Archival::AdvisoryLock.with_lock(user_id) do
          next unless archived?(user_id)

          delete_rows(user_id, ids)
          archive.update!(deleted_at: Time.current)
        end
      end

      def archived?(user_id)
        User.exists?(id: user_id, points_archive_state: User.points_archive_states[:archived])
      end

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
        per_import = Point.where(user_id:).group(:import_id).count
        Import.where(user_id:).find_each do |import|
          import.update_column(:points_count, per_import[import.id].to_i)
        end
      end
    end
  end
end

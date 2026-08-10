# frozen_string_literal: true

module Points
  module RawData
    class Clearer
      BATCH_SIZE = 10_000
      COOLING_PERIOD = 7.days

      # cooling_period: nil clears any verified archive immediately (manual
      # runbook paths); pass COOLING_PERIOD to only clear archives whose
      # verification has aged past the safety window (automated paths).
      def initialize(cooling_period: nil)
        @cooling_period = cooling_period
        @stats = { cleared: 0, skipped: 0 }
      end

      def call
        Rails.logger.info('Starting raw_data clearing for verified archives...')

        verified_archives.find_each do |archive|
          clear_archive_points(archive)
        end

        Rails.logger.info("Clearing complete: #{@stats}")
        @stats
      end

      def clear_user(user_id)
        Rails.logger.info("Starting raw_data clearing for user #{user_id}...")

        verified_archives(user_id: user_id).find_each do |archive|
          clear_archive_points(archive)
        end

        Rails.logger.info("Clearing complete for user #{user_id}: #{@stats}")
        @stats
      end

      def clear_specific_archive(archive_id)
        archive = Points::RawDataArchive.find(archive_id)

        if archive.verified_at.blank?
          Rails.logger.warn("Archive #{archive_id} not verified, skipping clear")
          return { cleared: 0, skipped: 0 }
        end

        clear_archive_points(archive)
      end

      def clear_month(user_id, year, month)
        archives = Points::RawDataArchive.for_month(user_id, year, month)
                                         .where.not(verified_at: nil)

        Rails.logger.info("Clearing #{archives.count} verified archives for #{year}-#{format('%02d', month)}...")

        archives.each { |archive| clear_archive_points(archive) }
      end

      private

      def verified_archives(user_id: nil)
        # Only archives that are verified but have points with non-empty raw_data
        scope = Points::RawDataArchive.where.not(verified_at: nil)
        scope = scope.where(user_id: user_id) if user_id
        scope = scope.where(verified_at: ..@cooling_period.ago) if @cooling_period
        scope.where(id: points_needing_clearing.select(:raw_data_archive_id).distinct)
      end

      def points_needing_clearing
        Point.where(raw_data_archived: true)
             .where.not(raw_data: {})
             .where.not(raw_data_archive_id: nil)
      end

      def clear_archive_points(archive)
        Rails.logger.info(
          "Clearing points for archive #{archive.id} " \
          "(#{archive.month_display}, chunk #{archive.chunk_number})..."
        )

        point_ids = Point.where(raw_data_archive_id: archive.id)
                         .where(raw_data_archived: true)
                         .where.not(raw_data: {})
                         .pluck(:id)

        if point_ids.empty?
          Rails.logger.info("No points to clear for archive #{archive.id}")
          return
        end

        cleared_count = clear_points_in_batches(point_ids, archive.id)
        @stats[:cleared] += cleared_count
        Rails.logger.info("✓ Cleared #{cleared_count} points for archive #{archive.id}")

        Yabeda.dawarich_archive.operations_total.increment({ operation: 'clear', status: 'success' })
        Yabeda.dawarich_archive.points_total.increment({ operation: 'removed' }, by: cleared_count)
      rescue StandardError => e
        ExceptionReporter.call(e, "Failed to clear points for archive #{archive.id}")
        Rails.logger.error("✗ Failed to clear archive #{archive.id}: #{e.message}")

        Yabeda.dawarich_archive.operations_total.increment({ operation: 'clear', status: 'failure' })
        raise if Archivable::UPSERT_CONTENTION_ERRORS.any? { |error_class| e.is_a?(error_class) }
      end

      def clear_points_in_batches(point_ids, archive_id)
        total_cleared = 0

        point_ids.each_slice(BATCH_SIZE) do |batch|
          Point.transaction do
            archive = Points::RawDataArchive.lock.find_by(id: archive_id)
            next unless archive_clearable?(archive)

            linked_ids = Point.raw_data_lock_order
                              .where(id: batch, raw_data_archived: true, raw_data_archive_id: archive_id)
                              .lock
                              .pluck(:id)
            cleared = Point.where(id: linked_ids, raw_data_archived: true, raw_data_archive_id: archive_id)
                           .update_all(raw_data: {}, lock_version: Arel.sql('lock_version'))
            # rubocop:enable Rails/SkipsModelValidations
            total_cleared += cleared
          end
        end

        total_cleared
      end

      def archive_clearable?(archive)
        return false if archive&.verified_at.blank?
        return true unless @cooling_period

        archive.verified_at <= @cooling_period.ago
      end
    end
  end
end

# frozen_string_literal: true

module Points
  module RawData
    class Clearer
      BATCH_SIZE = 10_000

      def initialize
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

      def clear_specific_archive(archive_id)
        archive = Points::RawDataArchive.find(archive_id)

        unless archive.verified_at.present?
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

      def verified_archives
        # Only archives that are verified but have points with non-empty raw_data
        Points::RawDataArchive
          .where.not(verified_at: nil)
          .where(id: points_needing_clearing.select(:raw_data_archive_id).distinct)
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

        cleared_count = clear_points_in_batches(point_ids)
        @stats[:cleared] += cleared_count
        Rails.logger.info("✓ Cleared #{cleared_count} points for archive #{archive.id}")

        # Report successful clear operation
        Metrics::Archives::Operation.new(
          operation: 'clear',
          status: 'success'
        ).call

        # Report points removed (cleared from database)
        Metrics::Archives::PointsArchived.new(
          count: cleared_count,
          operation: 'removed'
        ).call
      rescue StandardError => e
        ExceptionReporter.call(e, "Failed to clear points for archive #{archive.id}")
        Rails.logger.error("✗ Failed to clear archive #{archive.id}: #{e.message}")

        # Report failed clear operation
        Metrics::Archives::Operation.new(
          operation: 'clear',
          status: 'failure'
        ).call
      end

      def clear_points_in_batches(point_ids)
        total_cleared = 0

        point_ids.each_slice(BATCH_SIZE) do |batch|
          Point.transaction do
            Point.where(id: batch).update_all(raw_data: {})
            total_cleared += batch.size
          end
        end

        total_cleared
      end
    end
  end
end

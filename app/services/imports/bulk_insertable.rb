# frozen_string_literal: true

module Imports
  module BulkInsertable
    extend ActiveSupport::Concern

    private

    def bulk_insert_points(batch)
      return 0 if batch.empty?

      compacted = batch.compact
      unique_batch = compacted
                     .reject { |record| Points::NullIsland.lonlat?(record[:lonlat]) }
                     .uniq { |record| [record[:lonlat], record[:timestamp], record[:user_id]] }
      zero_skipped = compacted.size - compacted.count { |r| !Points::NullIsland.lonlat?(r[:lonlat]) }
      Rails.logger.info("[#{importer_name}] skipped #{zero_skipped} Null Island (0,0) points") if zero_skipped.positive?
      return 0 if unique_batch.empty?

      result = Point.upsert_all(
        unique_batch,
        unique_by: %i[lonlat timestamp user_id],
        returning: Arel.sql('id'),
        on_duplicate: :skip
      )

      inserted = result.length
      skipped  = unique_batch.length - inserted
      record_batch_counters(unique_batch.length, skipped)

      inserted
    rescue StandardError => e
      on_bulk_insert_error(e)
      create_import_error_notification("Failed to process #{importer_name} data: #{e.message}")
      0
    end

    def record_batch_counters(attempted, skipped)
      counters = { raw_points: attempted }
      counters[:doubles] = skipped if skipped.positive?
      Import.update_counters(import.id, counters)
    end

    def create_import_error_notification(message)
      Notification.create!(
        user_id: import.user_id,
        title: "#{importer_name} Import Error",
        content: message,
        kind: :error
      )
    end

    # Override in subclasses to add custom error handling (e.g. ExceptionReporter)
    def on_bulk_insert_error(exception); end

    def importer_name
      self.class.name.split('::').first
    end
  end
end

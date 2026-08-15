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

      if inserted.positive?
        Points::TileEpoch.bump(import.user_id, timestamps: unique_batch.map { |record| record[:timestamp] })
      end

      inserted
    rescue StandardError => e
      raise if atomic_bulk_insert?

      on_bulk_insert_error(e)
      create_import_error_notification("Failed to process #{importer_name} data: #{e.message}")
      0
    end

    # Importers that wrap the whole import in a transaction override this to true, so an
    # insert failure propagates and rolls back cleanly instead of poisoning the transaction
    # (a swallowed error would leave the connection aborted for the notification write).
    def atomic_bulk_insert?
      false
    end

    def record_batch_counters(attempted, skipped)
      counters = { raw_points: attempted }
      counters[:doubles] = skipped if skipped.positive?
      Import.update_counters(import.id, counters)
    end

    def create_import_error_notification(message)
      I18n.with_locale(import.user.locale) do
        Notification.create!(
          user_id: import.user_id,
          title: I18n.t('services.imports.bulk_insertable.importer_name_import_error', importer_name: importer_name),
          content: message,
          kind: :error
        )
      end
    end

    # Override in subclasses to add custom error handling (e.g. ExceptionReporter)
    def on_bulk_insert_error(exception); end

    def importer_name
      self.class.name.split('::').first
    end
  end
end

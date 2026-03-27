# frozen_string_literal: true

module Imports
  module BulkInsertable
    extend ActiveSupport::Concern

    private

    def bulk_insert_points(batch)
      return 0 if batch.empty?

      unique_batch = batch.compact.uniq { |record| [record[:lonlat], record[:timestamp], record[:user_id]] }

      Point.upsert_all(
        unique_batch,
        unique_by: %i[lonlat timestamp user_id],
        returning: false,
        on_duplicate: :skip
      )

      unique_batch.size
    rescue StandardError => e
      on_bulk_insert_error(e)
      create_import_error_notification("Failed to process #{importer_name} data: #{e.message}")
      0
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

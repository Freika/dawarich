# frozen_string_literal: true

module TransportationModes
  # Job to extract activity data from import files and update point raw_data.
  # This allows re-processing imports to extract activity information that
  # wasn't captured during the original import.
  #
  # Supports: Google Semantic History, Google Phone Takeout, Overland, OwnTracks
  #
  # Usage:
  #   TransportationModes::ImportBackfillJob.perform_later(import_id)
  #
  class ImportBackfillJob < ApplicationJob
    queue_as :low_priority

    def perform(import_id)
      import = Import.find_by(id: import_id)
      return unless import

      backfiller = ActivityBackfiller.new(import)
      return unless backfiller.supported?

      Rails.logger.info "Starting activity backfill for import #{import_id} (#{import.source})"

      backfiller.call

      # Reprocess affected tracks
      Tracks::Reprocessor.new(import: import).reprocess_for_import

      Rails.logger.info "Completed activity backfill for import #{import_id}"
    end
  end
end

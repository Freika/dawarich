# frozen_string_literal: true

module Imports
  class ExtractionMonitor
    STATES = %w[pending running].freeze
    LOGGED_IDS_LIMIT = 50

    def call
      oldest = STATES.index_with(0)
      stalled_ids = []

      in_flight.find_each do |import|
        stalled_ids << import.id if import.extraction_stalled?
        started_at = import.extraction_started_at
        next unless started_at

        state = import.additional_data_extraction_status
        oldest[state] = [oldest[state], (Time.current - started_at).to_i].max
      end

      report(oldest, stalled_ids.sort)
    end

    private

    def in_flight
      Import.extraction_in_flight.select(:id, :additional_data_extraction_status, :additional_data_extraction)
    end

    def report(oldest, stalled_ids)
      metrics = Yabeda.dawarich_imports
      oldest.each { |state, age| metrics.extraction_oldest_age_seconds.set({ state: state }, age) }
      metrics.extractions_stalled.set({}, stalled_ids.size)
      return if stalled_ids.empty?

      Rails.logger.warn(
        "event=imports.extractions_stalled count=#{stalled_ids.size} " \
        "import_ids=#{stalled_ids.first(LOGGED_IDS_LIMIT).join(',')}"
      )
    end
  end
end

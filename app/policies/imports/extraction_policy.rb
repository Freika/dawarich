# frozen_string_literal: true

module Imports
  class ExtractionPolicy < ApplicationPolicy
    def create?
      user.present? &&
        record.user == user &&
        record.additional_data_extraction_supported? &&
        !record.gpx_without_waypoints? &&
        !in_flight?
    end

    def destroy?
      user.present? &&
        record.user == user &&
        record.additional_data_extraction_supported? &&
        !in_flight? &&
        !record.additional_data_extraction_not_attempted?
    end

    private

    # A second job would rebuild segments underneath the one already running,
    # unless that run has gone stale and will never report back.
    def in_flight?
      record.extraction_in_flight? && !record.extraction_stalled?
    end
  end
end

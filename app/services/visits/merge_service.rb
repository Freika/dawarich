# frozen_string_literal: true

module Visits
  # Service to handle merging multiple visits into one
  class MergeService
    attr_reader :visits, :errors

    def initialize(visits)
      @visits = visits
      @errors = []
    end

    # Merges multiple visits into one
    # @return [Visit, nil] The merged visit or nil if merge failed
    def call
      return add_error('At least 2 visits must be selected for merging') if visits.length < 2

      merge_visits
    end

    private

    def add_error(message)
      @errors << message
      nil
    end

    def merge_visits
      Visit.transaction do
        # Use the first visit as the base for the merged visit
        base_visit = visits.first

        # Calculate the new start and end times
        earliest_start = visits.min_by(&:started_at).started_at
        latest_end = visits.max_by(&:ended_at).ended_at

        # Calculate the total duration (sum of all visit durations)
        total_duration = ((latest_end - earliest_start) / 60).round

        # Create a combined name
        combined_name = "Combined Visit (#{earliest_start.strftime('%b %d')} - #{latest_end.strftime('%b %d')})"

        # Update the base visit with the new data
        base_visit.update!(
          started_at: earliest_start,
          ended_at: latest_end,
          duration: total_duration,
          name: combined_name,
          status: 'confirmed' # Set status to confirmed for the merged visit
        )

        # Move all points from other visits to the base visit
        visits[1..].each do |visit|
          # Update points to associate with the base visit
          visit.points.update_all(visit_id: base_visit.id) # rubocop:disable Rails/SkipsModelValidations

          # Delete the other visit
          visit.destroy!
        end

        base_visit
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Failed to merge visits: #{e.message}")
      add_error(e.record.errors.full_messages.join(', '))
      nil
    end
  end
end

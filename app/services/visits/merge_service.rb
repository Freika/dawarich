# frozen_string_literal: true

module Visits
  # Service to handle merging multiple visits into one
  class MergeService
    attr_reader :visits, :errors, :base_visit

    def initialize(visits)
      @visits = visits
      @base_visit = visits.first
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
        update_base_visit(base_visit, visits)
        reassign_points(base_visit, visits)

        visits.drop(1).each(&:destroy!)

        base_visit
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Failed to merge visits: #{e.message}")
      add_error(e.record.errors.full_messages.join(', '))
      nil
    end

    def prepare_base_visit
      earliest_start = visits.min_by(&:started_at).started_at
      latest_end     = visits.max_by(&:ended_at).ended_at
      total_duration = ((latest_end - earliest_start) / 60).round
      combined_name  = "Combined Visit (#{visits.map(&:name).join(', ')})"

      {
        earliest_start:,
        latest_end:,
        total_duration:,
        combined_name:
      }
    end

    def update_base_visit(base_visit)
      base_visit_data = prepare_base_visit

      base_visit.update!(
        started_at: base_visit_data[:earliest_start],
        ended_at: base_visit_data[:latest_end],
        duration: base_visit_data[:total_duration],
        name: base_visit_data[:combined_name],
        status: 'confirmed'
      )
    end

    def reassign_points(base_visit, visits)
      visits[1..].each do |visit|
        visit.points.update_all(visit_id: base_visit.id) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end

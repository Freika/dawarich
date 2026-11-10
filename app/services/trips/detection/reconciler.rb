# frozen_string_literal: true

module Trips
  module Detection
    # Brings the user's Detected Trips in line with the detected periods
    # (ADR 0030). Only untouched Detected Trips are replaced or removed; every
    # other trip and every dismissed period wins over a detected period.
    class Reconciler
      def initialize(user, candidates)
        @user = user
        @candidates = candidates
      end

      # Returns the trips it created.
      def call
        created = Trip.transaction { reconcile }
        # Enqueued after commit, so the calculation never looks for a trip that is not there yet.
        created.each(&:enqueue_calculation_jobs)
        created
      end

      private

      attr_reader :user, :candidates

      def reconcile
        wanted = candidates.reject { |candidate| fixed_periods.any? { |period| overlap?(candidate, period) } }
        kept, stale = replaceable.to_a.partition { |trip| wanted.any? { |candidate| same_period?(trip, candidate) } }
        stale.each(&:destroy!)
        rename(kept)

        wanted.reject { |candidate| kept.any? { |trip| same_period?(trip, candidate) } }.map do |candidate|
          user.trips.create!(origin: :detected, started_at: candidate.started_at, ended_at: candidate.ended_at,
                             name: namer(candidate).call, skip_calculation_enqueue: true)
        end
      end

      # A Lite trip that began before the data window is fixed: its points there are unseen (ruling R19).
      def replaceable
        @replaceable ||= begin
          trips = user.trips.replaceable_by_detection
          user.plan_restricted? ? trips.where(started_at: user.data_window_start..) : trips
        end
      end

      # Every trip detection may not touch, plus every dismissed period.
      def fixed_periods
        @fixed_periods ||= user.trips.where.not(id: replaceable.select(:id)).pluck(:started_at, :ended_at) +
                           user.trip_detection_dismissals.pluck(:started_at, :ended_at)
      end

      def overlap?(candidate, (started_at, ended_at))
        candidate.started_at <= ended_at && started_at <= candidate.ended_at
      end

      def same_period?(trip, candidate)
        trip.started_at == candidate.started_at && trip.ended_at == candidate.ended_at
      end

      # ponytail: names every kept trip on every run (one countries and one city query each);
      # skip trips whose points did not change when a run is measured to be slow
      def rename(trips)
        trips.each do |trip|
          name = namer(trip).call
          trip.update_columns(name:, updated_at: Time.current) if trip.name != name
        end
      end

      def namer(period)
        Namer.new(user, started_at: period.started_at, ended_at: period.ended_at)
      end
    end
  end
end

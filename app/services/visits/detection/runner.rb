# frozen_string_literal: true

module Visits
  module Detection
    # Orchestrates the pipeline per monthly batch:
    #   CandidateLoader → DwellSweep → GapBridger → MovementReconciler →
    #   StayAssembler → PlaceAttributor (outside any txn) → ConfidenceScorer →
    #   Persister
    # then stitches machine visits across batch edges. Locking, plan-window
    # clamping and the entry seam live in Visits::SmartDetect.
    class Runner
      BATCH_THRESHOLD_DAYS = 31

      attr_reader :skipped_ranges

      def initialize(user, start_at:, end_at:)
        @user = user
        @start_at = start_at.to_i
        @end_at = end_at.to_i
        @policy = Policy.for(user)
        @skipped_ranges = []
      end

      def call
        started_clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        widen_window_to_machine_visits
        created = batch_ranges.flat_map { |batch_start, batch_end| run_batch(batch_start, batch_end) }
        created = stitch_adjacent(created)
        log_summary(created.size, started_clock)
        created
      end

      private

      attr_reader :user, :start_at, :end_at, :policy

      # The Persister replaces every machine visit its window overlaps, so the
      # window must be wide enough to regenerate them from their full point
      # range — otherwise a narrow realtime window would truncate a stay that
      # started before it.
      def widen_window_to_machine_visits
        overlapping = user.visits.machine_detected
                          .where('started_at <= ? AND ended_at >= ?',
                                 Time.zone.at(end_at), Time.zone.at(start_at))
        earliest = overlapping.minimum(:started_at)
        latest = overlapping.maximum(:ended_at)

        @start_at = [@start_at, earliest.to_i].min if earliest
        @end_at = [@end_at, latest.to_i].max if latest
      end

      # Persist runs even with zero stays: detection finding nothing is the
      # signal to clear stale machine output in the window.
      def run_batch(batch_start, batch_end)
        evidence = CandidateLoader.new(user, start_at: batch_start, end_at: batch_end, policy: policy).call
        if evidence[:skipped]
          @skipped_ranges << [batch_start, batch_end]
          return []
        end

        points_by_id = evidence[:points].index_by(&:id)
        stays = detect_stays(evidence, points_by_id)
        attributed = stays.empty? ? [] : attribute_and_score(stays, points_by_id)

        Persister.new(user, start_at: batch_start, end_at: batch_end, policy: policy)
                 .call(attributed, points_by_id: points_by_id)
      end

      def detect_stays(evidence, points_by_id)
        return [] if evidence[:points].empty?

        fragments = DwellSweep.new(policy).call(evidence[:points])
        bridged = GapBridger.new(policy).call(fragments)
        reconciled = MovementReconciler.new(policy).call(bridged, evidence[:segments])
        StayAssembler.new(policy).call(reconciled, points_by_id)
      end

      # Geocoder / place I/O — deliberately outside the persist transaction.
      def attribute_and_score(stays, points_by_id)
        attributor = PlaceAttributor.new(user, policy)

        stays.map do |stay|
          attributed = stay.merge(attributor.call(stay))
          attributed.merge(StayScoring.attributes(attributed, points_by_id, policy))
        end
      end

      def batch_ranges
        return [[start_at, end_at]] if ((end_at - start_at) / 1.day.to_i) <= BATCH_THRESHOLD_DAYS

        ranges = []
        cursor = Time.zone.at(start_at).beginning_of_month
        while cursor.to_i < end_at
          batch_start = [cursor.to_i, start_at].max
          batch_end = [(cursor.end_of_month + 1.day).beginning_of_day.to_i - 1, end_at].min
          ranges << [batch_start, batch_end]
          cursor = cursor.next_month
        end
        ranges
      end

      # A stay whose fixes straddle a batch edge is detected as two machine
      # visits; re-join them here. Beyond the ordinary merge gap the join is a
      # bridge, so it must also prove true silence: no recorded points between.
      def stitch_adjacent(created)
        return created if created.size < 2

        survivors = []
        created.sort_by(&:started_at).each do |visit|
          previous = survivors.last
          if previous && stitchable?(previous, visit)
            absorb(previous, visit)
          else
            survivors << visit
          end
        end
        survivors
      end

      def stitchable?(previous, visit)
        gap = visit.started_at.to_i - previous.ended_at.to_i
        return false if gap > policy.bridge_cap_s
        return false unless same_place?(previous, visit)
        return true if gap <= policy.merge_gap_s

        no_points_between?(previous.ended_at.to_i, visit.started_at.to_i)
      end

      def same_place?(previous, visit)
        a = previous.center
        b = visit.center
        return false unless a&.first && b&.first

        Geocoder::Calculations.distance_between(a, b, units: :km) * 1000 <= policy.stay_radius_m
      end

      def no_points_between?(from_ts, to_ts)
        !Point.where(user_id: user.id, timestamp: (from_ts + 1)..(to_ts - 1)).exists?
      end

      def absorb(previous, visit)
        Visit.transaction do
          Point.where(visit_id: visit.id).update_all(visit_id: previous.id)
          previous.update!(
            ended_at: visit.ended_at,
            duration: ((visit.ended_at.to_i - previous.started_at.to_i) / 60)
          )
          visit.destroy!
        end
        VisitRescore.call(previous, policy)
      end

      def log_summary(created_count, started_clock)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_clock) * 1000).to_i
        Rails.logger.info(
          "[Visits::Detection::Runner] user_id=#{user.id} range=#{start_at}..#{end_at} " \
          "version=#{Detection::VERSION} visits=#{created_count} duration_ms=#{duration_ms}"
        )
      end
    end
  end
end

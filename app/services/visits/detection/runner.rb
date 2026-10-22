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
      MIN_SPLIT_SECONDS = 1.hour.to_i

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
        widen_window_back_across_silence
      end

      # A stay can fall silent before the window opens (arrival fixes, a
      # silent night, departure fixes). Re-detect from its arrival so
      # GapBridger sees both sides of the silence. Tracking that resumed
      # elsewhere can't be bridged, so it isn't worth the wider scan.
      def widen_window_back_across_silence
        previous = user.visits.machine_detected
                       .where(ended_at: Time.zone.at(start_at - policy.bridge_cap_s)...Time.zone.at(start_at))
                       .order(ended_at: :desc).first
        return unless previous

        lat, lon, last_owned_ts = owned_fixes_summary(previous)
        center = lat ? [lat.to_f, lon.to_f] : previous.center
        silence_start = [previous.ended_at.to_i, last_owned_ts.to_i].max
        lookahead_end = [silence_start + policy.bridge_cap_s, end_at].min
        next_point = CandidateLoader.eligible_points(user)
                                    .where(timestamp: (silence_start + 1)..lookahead_end)
                                    .order(:timestamp).first
        return unless next_point && within_stay_radius?(center, [next_point.lat, next_point.lon])

        @start_at = previous.started_at.to_i
      end

      def owned_fixes_summary(visit)
        Point.where(user_id: user.id, visit_id: visit.id)
             .pick(Arel.sql('AVG(ST_Y(lonlat::geometry))'), Arel.sql('AVG(ST_X(lonlat::geometry))'),
                   Arel.sql('MAX(timestamp)'))
      end

      # Persist runs even with zero stays: detection finding nothing is the
      # signal to clear stale machine output in the window.
      def run_batch(batch_start, batch_end)
        evidence = CandidateLoader.new(user, start_at: batch_start, end_at: batch_end, policy: policy).call
        if evidence[:skipped]
          return split_batch(batch_start, batch_end) if batch_end - batch_start > MIN_SPLIT_SECONDS

          @skipped_ranges << [batch_start, batch_end]
          return []
        end

        points_by_id = evidence[:points].index_by(&:id)
        stays = detect_stays(evidence, points_by_id)
        attributed = stays.empty? ? [] : attribute_and_score(stays, points_by_id)

        Persister.new(user, start_at: batch_start, end_at: batch_end, policy: policy)
                 .call(attributed, points_by_id: points_by_id)
      end

      # Halves stitch back together through stitch_adjacent, like month edges.
      def split_batch(batch_start, batch_end)
        mid = batch_start + ((batch_end - batch_start) / 2)
        Rails.logger.info(
          "[Visits::Detection::Runner split] user_id=#{user.id} range=#{batch_start}..#{batch_end} mid=#{mid}"
        )
        run_batch(batch_start, mid) + run_batch(mid + 1, batch_end)
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

        stays.each_slice(100).flat_map do |batch|
          batch.zip(attributor.call_batch(batch)).map do |stay, attribution|
            attributed = stay.merge(attribution)
            attributed.merge(StayScoring.attributes(attributed, points_by_id, policy))
          end
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

        @stitch_centers = load_stitch_centers(created)
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
      ensure
        @stitch_centers = nil
      end

      def load_stitch_centers(visits)
        ActiveRecord::Associations::Preloader.new(records: visits, associations: %i[area place]).call
        centers = {}
        point_visits = visits.reject do |visit|
          centers[visit.id] = visit.center if visit.area || visit.place
        end
        point_visits.each_slice(100) do |batch|
          rows = Point.where(user_id: user.id, visit_id: batch.map(&:id))
                      .pluck(:visit_id, Arel.sql('ST_Y(lonlat::geometry)'), Arel.sql('ST_X(lonlat::geometry)'))
                      .group_by(&:first)
          batch.each do |visit|
            points = rows.fetch(visit.id, [])
            centers[visit.id] = if points.empty?
                                  [0, 0]
                                else
                                  [points.sum { |point| point[1] } / points.size.to_f,
                                   points.sum { |point| point[2] } / points.size.to_f]
                                end
          end
        end
        centers
      end

      def stitchable?(previous, visit)
        gap = visit.started_at.to_i - previous.ended_at.to_i
        return false if gap > policy.bridge_cap_s
        return false unless same_place?(previous, visit)
        return false if anchor_between?(previous.ended_at.to_i, visit.started_at.to_i)
        return true if gap <= policy.merge_gap_s

        no_points_between?(previous.ended_at.to_i, visit.started_at.to_i)
      end

      # A point-free silence can still hold a user-owned visit (imported or
      # manually created rows own no points) — bridging over it would overlap
      # an anchor.
      def anchor_between?(from_ts, to_ts)
        user.visits.where.not(id: user.visits.machine_detected.select(:id))
            .where('started_at < ? AND ended_at > ?', Time.zone.at(to_ts), Time.zone.at(from_ts))
            .exists?
      end

      def same_place?(previous, visit)
        within_stay_radius?(@stitch_centers.fetch(previous.id), @stitch_centers.fetch(visit.id))
      end

      def within_stay_radius?(here, there)
        return false unless here&.first && there&.first

        Geocoder::Calculations.distance_between(here, there, units: :km) * 1000 <= policy.stay_radius_m
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

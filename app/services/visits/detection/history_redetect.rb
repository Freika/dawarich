# frozen_string_literal: true

module Visits
  module Detection
    # Re-runs detection over a user's entire point history, month by month
    # (with a one-hour overlap so the Runner's window widening can stitch
    # stays across month edges), then backfills confidence onto legacy rows
    # that predate scoring. Shared by the user-facing FullHistoryRedetectJob
    # and the fleet rollout.
    class HistoryRedetect
      BATCH_OVERLAP_SECONDS = 1.hour.to_i

      Result = Struct.new(:visits_created, :months_total, :months_failed, keyword_init: true)

      def initialize(user)
        @user = user
      end

      def call
        min_ts = user.points.minimum(:timestamp)
        max_ts = user.points.maximum(:timestamp)
        purge_out_of_range_machine_visits(min_ts, max_ts)
        return Result.new(visits_created: 0, months_total: 0, months_failed: []) if min_ts.nil?

        months = monthly_ranges(min_ts, max_ts)
        visits_created = 0
        months_failed = []

        months.each do |range_start, range_end|
          visits_created += Visits::SmartDetect.new(user, start_at: range_start, end_at: range_end).call.size
        rescue StandardError => e
          months_failed << [range_start, range_end]
          Rails.logger.error(
            "[Visits::Detection::HistoryRedetect month_failed] user_id=#{user.id} " \
            "range=#{range_start}..#{range_end} class=#{e.class} message=#{e.message}"
          )
          ExceptionReporter.call(e)
        end

        backfill_legacy_confidence

        Result.new(visits_created: visits_created, months_total: months.size, months_failed: months_failed)
      end

      private

      attr_reader :user

      # Machine rows whose backing points are gone (deleted imports, pruned
      # history) sit outside every regeneration window and would otherwise
      # survive a "successful" redetect.
      def purge_out_of_range_machine_visits(min_ts, max_ts)
        scope = user.visits.active.where(status: :suggested, import_id: nil)
        if min_ts
          scope = scope.where.not('started_at <= ? AND ended_at >= ?',
                                  Time.zone.at(max_ts), Time.zone.at(min_ts))
        end

        wiped = MachineVisitWipe.call(scope)
        MachineVisitWipe.bust_month_caches(user, wiped.reject(&:demo).map(&:started_at))
      end

      def monthly_ranges(min_ts, max_ts)
        result = []
        cursor = Time.zone.at(min_ts).beginning_of_month
        while cursor.to_i < max_ts
          batch_start = [cursor.to_i, min_ts].max
          batch_end_raw = (cursor.end_of_month + 1.day).beginning_of_day.to_i - 1
          batch_end = [batch_end_raw + BATCH_OVERLAP_SECONDS, max_ts].min
          result << [batch_start, batch_end]
          cursor = cursor.next_month
        end
        result
      end

      # Confirmed rows survive re-detection untouched, but the UI gates on
      # confidence — give pre-scoring rows a score computed from their own
      # points. detection_version stays NULL: these are user-owned rows, not
      # regenerated machine output.
      def backfill_legacy_confidence
        policy = Policy.for(user)

        user.visits.active.where(confidence: nil)
            .includes(:area, :place)
            .find_in_batches(batch_size: 200) do |batch|
          points_by_visit = Point.where(visit_id: batch.map(&:id))
                                 .select(:id, :visit_id, :accuracy, :lonlat)
                                 .group_by(&:visit_id)
          batch.each { |visit| VisitRescore.call(visit, policy, points: points_by_visit[visit.id] || []) }
        end
      end
    end
  end
end

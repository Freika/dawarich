# frozen_string_literal: true

module Visits
  module Detection
    # Overlay-aware write layer. Confirmed visits and tombstones are fixed
    # anchors: machine stays are trimmed around them by exact interval
    # exclusion (no fuzzy dedup). Machine `suggested` rows in the window are
    # replaced wholesale in one transaction, which makes detection idempotent
    # by construction. The per-user advisory xact lock lives HERE — the single
    # lock primitive for every machine writer — so compute and geocoder I/O
    # stay outside any lock or transaction.
    class Persister
      include Visits::AdvisoryLockable

      DEFAULT_NAME = 'Unknown Location'

      def initialize(user, start_at:, end_at:, policy:)
        @user = user
        @start_at = start_at.to_i
        @end_at = end_at.to_i
        @policy = policy
      end

      # Anchors are read under the lock so a visit confirmed mid-run can't be
      # overlapped; trimming is pure arithmetic and cheap enough to hold it.
      def call(stays, points_by_id: {})
        created = []
        replaced = []
        ActiveRecord::Base.transaction do
          acquire_user_lock
          anchors = anchor_visits
          prepared = stays.filter_map { |stay| trim_to_anchors(stay, anchors, points_by_id) }
          replaced = delete_machine_rows
          prepared.each do |stay|
            visit = insert_stay(stay)
            created << visit if visit
          end
        end
        flush_replacement_side_effects(replaced)

        created
      end

      private

      attr_reader :user, :start_at, :end_at, :policy

      # Transaction-scoped (xact) rather than session-scoped so it survives
      # PgBouncer transaction pooling.
      def acquire_user_lock
        return unless advisory_locks_enabled?

        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?)', user.id.to_i])
        )
      end

      def window_overlap(scope)
        scope.where('started_at <= ? AND ended_at >= ?', Time.zone.at(end_at), Time.zone.at(start_at))
      end

      # Machine output = active suggested rows this detector produced;
      # everything else in the window (confirmed, declined, soft-deleted, and
      # importer-written visits, which cannot be re-derived from points) is an
      # anchor.
      def machine_scope
        window_overlap(user.visits.active.where(status: :suggested, import_id: nil))
      end

      def anchor_visits
        window_overlap(
          user.visits.where('deleted_at IS NOT NULL OR status != 0 OR import_id IS NOT NULL')
        ).to_a
      end

      def delete_machine_rows
        MachineVisitWipe.call(machine_scope)
      end

      def flush_replacement_side_effects(replaced)
        rows = replaced.reject(&:demo)
        return if rows.empty?

        place_ids = rows.filter_map(&:place_id).uniq
        ActiveJob.perform_all_later(place_ids.map { |id| Places::DeleteIfOrphanJob.new(id) })
        MachineVisitWipe.bust_month_caches(user, rows.map(&:started_at))
      end

      def trim_to_anchors(stay, anchors, points_by_id)
        overlapping = anchors.select do |anchor|
          anchor.started_at.to_i < stay[:end_ts] && anchor.ended_at.to_i > stay[:start_ts]
        end
        return stay if overlapping.empty?

        bounds = shrink_around(stay, overlapping)
        return nil if bounds.nil? || (bounds[1] - bounds[0]) < policy.min_dwell_s

        retimed(stay, bounds, points_by_id)
      end

      # A trimmed stay is a different stay: its confidence must reflect the
      # interval that actually persists, not the one detection scored.
      def retimed(stay, bounds, points_by_id)
        duration = bounds[1] - bounds[0]
        point_ids = ids_within(stay[:point_ids], bounds, points_by_id)
        trimmed = stay.merge(
          start_ts: bounds[0], end_ts: bounds[1], duration_s: duration,
          point_ids: point_ids, count: point_ids.size,
          bridged_s: [stay[:bridged_s].to_i, duration].min,
          radius: radius_within(stay, point_ids, points_by_id)
        )
        trimmed.merge(StayScoring.attributes(trimmed, points_by_id, policy))
      end

      def radius_within(stay, point_ids, points_by_id)
        points = point_ids.filter_map { |id| points_by_id[id] }
        return stay[:radius] if points.empty?

        points.map do |point|
          Geocoder::Calculations.distance_between(
            [stay[:center_lat], stay[:center_lon]], [point.lat, point.lon], units: :km
          ) * 1000
        end.max
      end

      def shrink_around(stay, anchors)
        from = stay[:start_ts]
        to = stay[:end_ts]

        anchors.sort_by(&:started_at).each do |anchor|
          anchor_start = anchor.started_at.to_i
          anchor_end = anchor.ended_at.to_i
          next if anchor_end <= from || anchor_start >= to

          if anchor_start <= from && anchor_end >= to
            return nil
          elsif anchor_start > from && anchor_end < to
            # Anchor strictly inside: keep the longer flank.
            if (anchor_start - from) >= (to - anchor_end)
              to = anchor_start
            else
              from = anchor_end
            end
          elsif anchor_start <= from
            from = anchor_end
          else
            to = anchor_start
          end
        end

        [from, to]
      end

      def ids_within(point_ids, bounds, points_by_id)
        Array(point_ids).select do |id|
          point = points_by_id[id]
          point.nil? || point.timestamp.between?(bounds[0], bounds[1])
        end
      end

      # The unique index (user, started_at, place) is the collision backstop:
      # a duplicate drops that one row instead of poisoning the batch.
      def insert_stay(stay)
        ActiveRecord::Base.transaction(requires_new: true) do
          visit = Visit.create!(
            user: user,
            area: stay[:area],
            place: stay[:place],
            started_at: Time.zone.at(stay[:start_ts]),
            ended_at: Time.zone.at(stay[:end_ts]),
            duration: (stay[:end_ts] - stay[:start_ts]) / 60,
            name: stay[:name].presence || DEFAULT_NAME,
            status: :suggested,
            detection_version: Detection::VERSION,
            confidence: stay[:confidence],
            confidence_breakdown: stay[:confidence_breakdown] || {}
          )

          claim_points(stay[:point_ids], visit)
          visit
        end
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      # Only unowned points are claimed — anchors keep theirs (the machine
      # rows in the window were just destroyed, which nullified their cache).
      def claim_points(point_ids, visit)
        return if point_ids.blank?

        Point.where(id: point_ids, visit_id: nil).update_all(visit_id: visit.id)
      end
    end
  end
end

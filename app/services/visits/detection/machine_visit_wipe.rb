# frozen_string_literal: true

module Visits
  module Detection
    # Bulk removal of machine visit rows. Per-row destroy callbacks would
    # enqueue one orphan-cleanup job and one cache delete per visit, so
    # callers delete in bulk here and run the side effects batched, using
    # the returned rows.
    class MachineVisitWipe
      Row = Struct.new(:id, :place_id, :started_at, :demo)
      Result = Struct.new(:rows, :suggested_place_ids)

      def self.call(scope)
        rows = scope.pluck(:id, :place_id, :started_at, :demo).map { |values| Row.new(*values) }
        return Result.new(rows, []) if rows.empty?

        ids = rows.map(&:id)
        suggested_place_ids = PlaceVisit.where(visit_id: ids).distinct.pluck(:place_id)
        Point.where(visit_id: ids).update_all(visit_id: nil)
        PlaceVisit.where(visit_id: ids).delete_all
        Visit.where(id: ids).delete_all
        Result.new(rows, suggested_place_ids)
      end

      # Every wipe owes the same debts: orphan-cleanup for the places the
      # rows referenced (directly or through suggested-place joins) and a
      # month-summary cache bust for the days they occupied.
      def self.flush_side_effects(user, result)
        return if result.rows.empty?

        place_ids = (result.rows.filter_map(&:place_id) + result.suggested_place_ids).uniq
        ActiveJob.perform_all_later(place_ids.map { |id| Places::DeleteIfOrphanJob.new(id) })
        bust_month_caches(user, result.rows.map(&:started_at))
        Rails.logger.info(
          "[Visits::Detection::MachineVisitWipe] user_id=#{user.id} " \
          "wiped=#{result.rows.size} orphan_candidates=#{place_ids.size}"
        )
      end

      def self.bust_month_caches(user, times)
        return if times.empty?

        tz = user.safe_settings.timezone.presence || 'UTC'
        Time.use_zone(tz) do
          times.map { |t| t.in_time_zone.to_date.beginning_of_month }.uniq.each do |month_start|
            Rails.cache.delete(Timeline::MonthSummary.cache_key_for(user, month_start))
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[Visits::Detection::MachineVisitWipe] month cache bust failed: #{e.class}: #{e.message}")
      end
    end
  end
end

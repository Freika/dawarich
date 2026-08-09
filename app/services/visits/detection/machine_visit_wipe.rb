# frozen_string_literal: true

module Visits
  module Detection
    # Bulk removal of machine visit rows. Per-row destroy callbacks would
    # enqueue one orphan-cleanup job and one cache delete per visit, so
    # callers delete in bulk here and run the side effects batched, using
    # the returned rows.
    class MachineVisitWipe
      Row = Struct.new(:id, :place_id, :started_at, :demo)

      def self.call(scope)
        doomed = scope.pluck(:id, :place_id, :started_at, :demo).map { |values| Row.new(*values) }
        return doomed if doomed.empty?

        ids = doomed.map(&:id)
        Point.where(visit_id: ids).update_all(visit_id: nil)
        PlaceVisit.where(visit_id: ids).delete_all
        Visit.where(id: ids).delete_all
        doomed
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

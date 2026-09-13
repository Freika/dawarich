# frozen_string_literal: true

module Visits
  module Detection
    # Recomputes confidence for a persisted visit from its own slim point
    # rows — shared by the legacy backfill and batch-edge stitching. Pass
    # preloaded points when batching; otherwise they are fetched here.
    class VisitRescore
      def self.call(visit, policy, points: nil)
        points ||= Point.where(visit_id: visit.id).select(:id, :accuracy, :lonlat).to_a
        # No point evidence means any score would be fabricated — an unscored
        # visit renders at full strength instead of a false low band.
        return if points.empty?

        center = center_for(visit, points)
        return if center && center.first.blank?

        result = Visits::ConfidenceScorer.new(
          duration_seconds: visit.ended_at.to_i - visit.started_at.to_i,
          point_count: points.size,
          accuracies: points.map(&:accuracy),
          radius_meters: radius_from(points, center),
          stay_radius_meters: policy.stay_radius_m,
          min_points: policy.min_points,
          place_match: place_match_for(visit)
        ).call

        visit.update_columns(confidence: result[:score], confidence_breakdown: result[:breakdown])
      end

      def self.center_for(visit, points)
        if visit.area
          [visit.area.lat, visit.area.lon]
        elsif visit.place
          [visit.place.lat, visit.place.lon]
        elsif points.any?
          [points.sum(&:lat) / points.size.to_f, points.sum(&:lon) / points.size.to_f]
        end
      end

      def self.place_match_for(visit)
        return :area if visit.area_id
        return :place if visit.place_id

        nil
      end

      def self.radius_from(points, center)
        return 15 if points.empty? || center.nil?

        max = points.map do |point|
          Geocoder::Calculations.distance_between(center, [point.lat, point.lon], units: :km) * 1000
        end.max
        [max, 15].max
      end
    end
  end
end

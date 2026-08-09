# frozen_string_literal: true

module Visits
  module Detection
    # The single merge layer of the pipeline. Chain-merges same-place
    # fragments within the merge gap (brief re-entries whose excursion the
    # reconciler already vetoed away), then — and only then — applies the
    # minimum dwell / minimum points filters, then finalizes each stay's
    # center and radius from its actual points.
    class StayAssembler
      MIN_RADIUS_M = 15
      DEFAULT_ACCURACY_M = 50

      def initialize(policy)
        @policy = policy
      end

      # Finalize before gating: boundary snapping may have dropped fixes from
      # the interval, and the dwell/point floors must judge what actually
      # persists.
      def call(fragments, points_by_id)
        chain_merge(fragments)
          .map { |f| finalize(f, points_by_id) }
          .select { |stay| keep?(stay) }
      end

      private

      attr_reader :policy

      def chain_merge(fragments)
        fragments.each_with_object([]) do |fragment, merged|
          current = fragment.dup
          previous = merged.last

          if previous && mergeable?(previous, current)
            merge_into(previous, current)
          else
            merged << current
          end
        end
      end

      def mergeable?(previous, current)
        gap = current[:start_ts] - previous[:end_ts]
        return false if gap > policy.merge_gap_s

        distance_m(previous[:center_lat], previous[:center_lon],
                   current[:center_lat], current[:center_lon]) <= policy.stay_radius_m
      end

      def merge_into(previous, current)
        a = previous[:count]
        b = current[:count]
        total = a + b

        previous[:center_lat] = ((previous[:center_lat] * a) + (current[:center_lat] * b)) / total
        previous[:center_lon] = ((previous[:center_lon] * a) + (current[:center_lon] * b)) / total
        previous[:point_ids] += current[:point_ids]
        previous[:end_ts] = [previous[:end_ts], current[:end_ts]].max
        previous[:count] = total
        previous[:bridged_s] = previous.fetch(:bridged_s, 0) + current.fetch(:bridged_s, 0)
        previous[:corroborated] = previous[:corroborated] || current[:corroborated] || false
      end

      # Bridged silence counts toward dwell — the whole point of bridging is
      # that the user was there for it.
      def keep?(fragment)
        (fragment[:end_ts] - fragment[:start_ts]) >= policy.min_dwell_s &&
          fragment[:count] >= policy.min_points
      end

      # Boundary snapping can move a fragment's interval off some of its own
      # fixes; those points are movement, not dwell, and must not shape the
      # center or get claimed.
      def finalize(fragment, points_by_id)
        point_ids = ids_within_interval(fragment, points_by_id)
        points = point_ids.filter_map { |id| points_by_id[id] }
        center_lat, center_lon = weighted_center(points, fragment)

        {
          point_ids: point_ids,
          start_ts: fragment[:start_ts],
          end_ts: fragment[:end_ts],
          duration_s: fragment[:end_ts] - fragment[:start_ts],
          center_lat: center_lat,
          center_lon: center_lon,
          radius: radius_m(points, center_lat, center_lon),
          count: point_ids.size,
          bridged_s: fragment.fetch(:bridged_s, 0),
          corroborated: fragment.fetch(:corroborated, false)
        }
      end

      def ids_within_interval(fragment, points_by_id)
        Array(fragment[:point_ids]).select do |id|
          point = points_by_id[id]
          point.nil? || point.timestamp.between?(fragment[:start_ts], fragment[:end_ts])
        end
      end

      def weighted_center(points, fragment)
        return [fragment[:center_lat], fragment[:center_lon]] if points.empty?

        total = 0.0
        lat_sum = 0.0
        lon_sum = 0.0

        points.each do |point|
          weight = 1.0 / [point.accuracy || DEFAULT_ACCURACY_M, 1].max
          lat_sum += point.lat * weight
          lon_sum += point.lon * weight
          total += weight
        end

        [lat_sum / total, lon_sum / total]
      end

      def radius_m(points, center_lat, center_lon)
        return MIN_RADIUS_M if points.empty?

        max = points.map { |p| distance_m(center_lat, center_lon, p.lat, p.lon) }.max
        [max, MIN_RADIUS_M].max.round
      end

      def distance_m(lat1, lon1, lat2, lon2)
        Geocoder::Calculations.distance_between([lat1, lon1], [lat2, lon2], units: :km) * 1000
      end
    end
  end
end

# frozen_string_literal: true

module Maps
  class PrivacyZoneTrackMasker
    def initialize(masker)
      @masker = masker
    end

    def call(geojson)
      features = Array(geojson[:features])
      segments = features.flat_map { |feature| drawn_segments(feature[:properties]) }
      results = clip(features.map { |feature| feature[:geometry] } + segments.map { |segment| line(segment) })

      clipped_segments = {}.compare_by_identity
      segments.each_with_index { |segment, index| clipped_segments[segment] = results[features.size + index].first }

      masked = features.zip(results).filter_map do |feature, (geometry, touched)|
        next if geometry.nil?

        feature.merge(geometry:, properties: mask_properties(feature[:properties], clipped_segments, touched))
      end
      geojson.merge(features: masked)
    end

    private

    def drawn_segments(properties)
      return [] unless properties.is_a?(Hash) && properties[:segments].is_a?(Array)

      properties[:segments].select { |segment| segment[:coordinates].present? }
    end

    def line(segment)
      type = segment[:coordinates].first&.first.is_a?(Array) ? 'MultiLineString' : 'LineString'
      { type:, coordinates: segment[:coordinates] }
    end

    def mask_properties(properties, clipped_segments, touched)
      return properties unless properties.is_a?(Hash) && properties[:segments].is_a?(Array)

      segments = properties[:segments].filter_map do |segment|
        if segment[:coordinates].present?
          geometry = clipped_segments[segment]
          geometry && segment.merge(coordinates: geometry[:coordinates])
        elsif !touched
          segment
        end
      end
      properties.merge(segments:)
    end

    def clip(geometries)
      results = geometries.map { |geometry| [geometry, false] }
      candidates = geometries.each_index.select { |index| near_zone?(geometries[index]) }
      return results if candidates.empty?

      chosen = candidates.map { |index| geometries[index] }
      clip_rows(chosen.map(&:to_json), candidate_masker(chosen)).each do |ordinal, touched, json|
        next unless ActiveModel::Type::Boolean.new.cast(touched)

        results[candidates[ordinal.to_i - 1]] = [json && JSON.parse(json, symbolize_names: true), true]
      end
      results
    end

    def near_zone?(geometry)
      return false if geometry.nil?

      lons, lats = coordinates(geometry.deep_symbolize_keys).transpose
      return true if lons.nil?

      @masker.near(min_lon: lons.min, min_lat: lats.min, max_lon: lons.max, max_lat: lats.max).any?
    end

    def coordinates(geometry)
      case geometry[:type].to_s
      when 'LineString', 'MultiPoint' then geometry[:coordinates]
      when 'MultiLineString', 'Polygon' then geometry[:coordinates].flatten(1)
      when 'Point' then [geometry[:coordinates]]
      else []
      end
    end

    def clip_rows(texts, masker)
      connection = ActiveRecord::Base.connection
      list = texts.map { |text| connection.quote(text) }.join(', ')
      connection.select_rows(<<~SQL.squish)
        SELECT ordinal, touched, CASE WHEN ST_IsEmpty(clipped) THEN NULL ELSE ST_AsGeoJSON(clipped) END
        FROM (
          SELECT input.ordinal, test.touched,
                 CASE WHEN test.touched THEN #{masker.clip_sql('source.geom')} ELSE source.geom END AS clipped
          FROM unnest(ARRAY[#{list}]::text[]) WITH ORDINALITY AS input(json, ordinal)
          CROSS JOIN LATERAL (SELECT ST_SetSRID(ST_GeomFromGeoJSON(input.json), 4326) AS geom) AS source
          CROSS JOIN LATERAL (SELECT #{masker.touches_sql('source.geom')} AS touched OFFSET 0) AS test
          OFFSET 0
        ) AS result
      SQL
    end

    def candidate_masker(geometries)
      points = geometries.map { |geometry| coordinates(geometry.deep_symbolize_keys) }
      return @masker if points.any?(&:blank?)

      lons, lats = points.flatten(1).transpose

      @masker.near(min_lon: lons.min, min_lat: lats.min, max_lon: lons.max, max_lat: lats.max)
    end
  end
end

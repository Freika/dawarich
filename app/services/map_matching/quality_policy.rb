# frozen_string_literal: true

module MapMatching
  class QualityPolicy
    VERSION = 1

    Decision = Data.define(:accepted, :reasons) do
      def accepted?
        accepted
      end
    end

    def self.call(geometry:, stats:, input_point_count:)
      new(geometry:, stats:, input_point_count:).call
    end

    def initialize(geometry:, stats:, input_point_count:)
      @geometry = geometry
      @stats = stats
      @input_point_count = input_point_count
    end

    def call
      reasons = []
      reasons << 'invalid_geometry' unless valid_geometry?
      reasons << 'no_matched_points' unless matched_points.positive?
      reasons << 'invalid_input_point_count' unless input_point_count.to_i >= 2

      Decision.new(accepted: reasons.empty?, reasons:)
    end

    private

    attr_reader :geometry, :stats, :input_point_count

    def matched_points
      stats.fetch('matched', 0).to_i + stats.fetch('interpolated', 0).to_i
    end

    def valid_geometry?
      return false unless geometry.is_a?(Hash)

      lines = case geometry['type']
              when 'LineString' then [geometry['coordinates']]
              when 'MultiLineString' then geometry['coordinates']
              else return false
              end

      lines.is_a?(Array) && lines.present? && lines.all? do |line|
        line.is_a?(Array) && line.size >= 2 && line.all? { |coordinate| valid_coordinate?(coordinate) }
      end
    end

    def valid_coordinate?(coordinate)
      coordinate.is_a?(Array) && coordinate.size >= 2 &&
        coordinate.first(2).all? { |value| value.is_a?(Numeric) && value.finite? }
    end
  end
end

# frozen_string_literal: true

module MapMatching
  class Composer
    def self.call(lines)
      new(lines).call
    end

    def initialize(lines)
      @lines = lines
    end

    def call
      line_strings = lines.filter_map { |coordinates| build_line(coordinates) }
      return if line_strings.empty?

      factory.multi_line_string(line_strings)
    end

    private

    attr_reader :lines

    def build_line(coordinates)
      return unless coordinates.is_a?(Array) && coordinates.size >= 2

      factory.line_string(coordinates.map { |lon, lat| factory.point(lon, lat) })
    end

    def factory
      @factory ||= RGeo::Geographic.spherical_factory(srid: 4326)
    end
  end
end

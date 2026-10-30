# frozen_string_literal: true

module Achievements
  class SeriesArtwork
    COLORS = %w[#82c8f0 #8ad58b #edc564 #db976c].freeze

    def self.call(card, public: false)
      return CityArtwork.new(card, public: public).call if card.series == 'city'

      return ParkArtwork.call(card) if card.series == 'park'

      case card.series
      when 'seasons'
        sectors = 4.times.map { |i| sector(i * 90, (i + 1) * 90, 43, 24) }
        mask = card.data.fetch('season_mask', 0)
        { path: sectors.join(' '), viewbox: '-50 -50 100 100',
          unvisited_path: sectors.each_with_index.filter_map { |path, i| path if (mask & (1 << i)).zero? }.join(' '),
          colors: sectors.each_with_index.map { |path, i| { path: path, color: COLORS[i] } } }
      when 'return'
        rings = [15, 29, 43].map { |radius| ring(radius, radius - 5) }
        { path: rings.join(' '), viewbox: '-50 -50 100 100',
          unvisited_path: rings.drop(card.level).join(' ') }
      when 'milestone'
        GlobeArtwork.call(card)
      else
        # A symbolic forest avoids publishing an exact visited position.
        trees = [-25, 0, 25].map do |x|
          polygon([[x, -37], [x + 17, -8], [x + 10, -8], [x + 22, 17], [x + 4, 17],
                   [x + 4, 35], [x - 4, 35], [x - 4, 17], [x - 22, 17], [x - 10, -8], [x - 17, -8]])
        end
        filled = if card.series == 'park'
                   card.unlocked? ? 3 : 0
                 else
                   card.level
                 end
        { path: trees.join(' '), viewbox: '-50 -50 100 100', unvisited_path: trees.drop(filled).join(' ') }
      end
    end

    def self.sector(from, to, outer, inner)
      angles = (from..to).step(3).to_a
      angles << to unless angles.last == to
      polygon(angles.map { |angle| point(outer, angle) } + angles.reverse.map { |angle| point(inner, angle) })
    end

    def self.ring(outer, inner)
      outside = polygon((0...360).step(6).map { |angle| point(outer, angle) })
      inside = polygon((0...360).step(6).to_a.reverse.map { |angle| point(inner, angle) })
      "#{outside} #{inside}"
    end

    def self.point(radius, angle)
      radians = angle * Math::PI / 180
      [(radius * Math.cos(radians)).round(4), (radius * Math.sin(radians)).round(4)]
    end

    def self.polygon(points)
      "M #{points.map { |x, y| "#{x} #{y}" }.join(' L ')} Z"
    end
  end
end

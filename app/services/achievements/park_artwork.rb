# frozen_string_literal: true

module Achievements
  class ParkArtwork
    def self.call(card)
      territory = Exploration::Territory.find_by(id: card.data['territory_id'], dataset_id: card.data['dataset_id'],
                                                 kind: 'park')
      return unless territory

      row = ApplicationRecord.connection.select_rows(<<~SQL).first
        SELECT ST_AsSVG(ST_SimplifyPreserveTopology(boundary,0.00003),0,6),
          ST_XMin(boundary),-ST_YMax(boundary),ST_XMax(boundary)-ST_XMin(boundary),
          ST_YMax(boundary)-ST_YMin(boundary) FROM exploration_territories WHERE id=#{territory.id}
      SQL
      path, x, y, width, height = row
      { path: path, viewbox: [x, y, width, height].join(' '), unvisited_path: card.unlocked? ? nil : path }
    end
  end
end

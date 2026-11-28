# frozen_string_literal: true

module Achievements
  class CityArtwork
    def initialize(card, public: false)
      @card = card
      @public = public
    end

    def call
      territory = Exploration::Territory.find_by(id: @card.data['territory_id'])
      return unless territory

      snapshot = Exploration::Snapshot.find_by(id: @card.data['snapshot_id'], user_id: @card.user_id)
      return unless snapshot

      geometry = opened_geometry_sql(snapshot)
      sql = <<~SQL
        WITH territory AS (SELECT land FROM exploration_territories WHERE id=#{territory.id}),
        opened AS (SELECT ST_CollectionExtract(ST_Intersection(t.land,COALESCE((#{geometry}),
          ST_GeomFromText('MULTIPOLYGON EMPTY',4326))),3) AS geom FROM territory t),
        shapes AS (SELECT t.land AS whole,ST_Difference(t.land,o.geom) AS missing FROM territory t CROSS JOIN opened o)
        SELECT ST_AsSVG(ST_SimplifyPreserveTopology(whole,0.00003),0,6),
               ST_XMin(whole),-ST_YMax(whole),ST_XMax(whole)-ST_XMin(whole),ST_YMax(whole)-ST_YMin(whole),
               ST_AsSVG(ST_SimplifyPreserveTopology(missing,0.00003),0,6) FROM shapes
      SQL
      path, x, y, width, height, missing = ApplicationRecord.connection.select_rows(sql).first
      missing = nil if @public && !@card.city_selection&.share_mosaic?
      { path: path, viewbox: [x, y, width, height].join(' '), unvisited_path: missing }
    end

    private

    def opened_geometry_sql(snapshot)
      return 'SELECT NULL::geometry' if @public && !@card.city_selection&.share_mosaic?

      exclusions = ''
      if @public
        masker = Maps::PrivacyZoneMasker.new(@card.user)
        exclusions = "AND NOT #{masker.touches_sql('c.geom')}" if masker.any?
      end
      <<~SQL.squish
        SELECT ST_UnaryUnion(ST_Collect(c.geom)) FROM exploration_openings o JOIN exploration_cells c ON c.id=o.cell_id
        JOIN exploration_territories t ON t.id=#{@card.data.fetch('territory_id').to_i}
          AND c.geom && t.boundary AND ST_Intersects(c.geom,t.boundary)
        WHERE o.snapshot_id=#{snapshot.id} #{exclusions}
      SQL
    end
  end
end

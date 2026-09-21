# frozen_string_literal: true

module Areas
  class Nearby
    MAX_RESULTS = 10

    MIN_QUERY_LENGTH = 2

    def initialize(user:, latitude:, longitude:, radius:, limit: MAX_RESULTS, query: nil)
      @user = user
      @latitude = latitude.to_f
      @longitude = longitude.to_f
      @radius = radius.to_f
      @limit = limit.to_i
      @query = query.to_s.strip
    end

    def call
      radius_meters = @radius * 1000
      origin  = "ST_SetSRID(ST_MakePoint(#{@longitude}, #{@latitude}), 4326)::geography"
      area_pt = <<~SQL.squish
        ST_SetSRID(
          ST_MakePoint(
            COALESCE(places.longitude, areas.longitude),
            COALESCE(places.latitude, areas.latitude)
          ), 4326
        )::geography
      SQL
      base_scope = @user.areas
                        .joins('LEFT JOIN legacy_area_place_mappings mappings ON mappings.area_id = areas.id')
                        .joins('LEFT JOIN places ON places.id = mappings.place_id')

      scope = base_scope.where(Arel.sql("ST_DWithin(#{area_pt}, #{origin}, #{radius_meters})"))
      if @query.length >= MIN_QUERY_LENGTH
        scope = scope.or(
          base_scope.where(
            'COALESCE(places.name, areas.name) ILIKE ?', "%#{Area.sanitize_sql_like(@query)}%"
          )
        )
      end

      scope
        .select(
          'areas.*',
          'COALESCE(places.name, areas.name) AS resolved_name',
          'COALESCE(places.latitude, areas.latitude) AS resolved_latitude',
          'COALESCE(places.longitude, areas.longitude) AS resolved_longitude',
          'COALESCE(places.visit_radius, areas.radius) AS resolved_radius'
        )
        .order(Arel.sql("ST_Distance(#{area_pt}, #{origin}) ASC"))
        .limit(@limit)
        .map { |area| format(area) }
    end

    private

    def format(area)
      {
        id: area.id,
        name: area.resolved_name,
        latitude: area.resolved_latitude.to_f,
        longitude: area.resolved_longitude.to_f,
        radius: area.resolved_radius,
        source: 'area'
      }
    end
  end
end

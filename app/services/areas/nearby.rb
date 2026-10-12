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
      area_pt = 'ST_SetSRID(ST_MakePoint(areas.longitude, areas.latitude), 4326)::geography'

      scope = @user.areas.where(Arel.sql("ST_DWithin(#{area_pt}, #{origin}, #{radius_meters})"))
      if @query.length >= MIN_QUERY_LENGTH
        scope = scope.or(@user.areas.where('name ILIKE ?', "%#{Area.sanitize_sql_like(@query)}%"))
      end

      scope
        .order(Arel.sql("ST_Distance(#{area_pt}, #{origin}) ASC"))
        .limit(@limit)
        .map { |area| format(area) }
    end

    private

    def format(area)
      {
        id: area.id,
        name: area.name,
        latitude: area.latitude.to_f,
        longitude: area.longitude.to_f,
        radius: area.radius,
        source: 'area'
      }
    end
  end
end

# frozen_string_literal: true

module Places
  class UserSearch
    MIN_QUERY_LENGTH = 2

    def initialize(user:, latitude:, longitude:, radius:, limit:, query: nil)
      @user = user
      @latitude = latitude.to_f
      @longitude = longitude.to_f
      @radius = radius.to_f
      @limit = limit.to_i
      @query = query.to_s.strip
    end

    def call
      scope
        .with_distance([@latitude, @longitude], :km)
        .order(:distance_in_km)
        .limit(@limit)
        .map { |place| format(place) }
    end

    private

    def scope
      return base_scope.near([@latitude, @longitude], @radius, :km) if @query.length < MIN_QUERY_LENGTH

      base_scope.where('name ILIKE ?', "%#{Place.sanitize_sql_like(@query)}%")
    end

    def base_scope
      @base_scope ||= @user.places.where.not(lonlat: nil).map_visible(@user)
    end

    def format(place)
      {
        id: place.id,
        name: place.name,
        latitude: place.lat,
        longitude: place.lon,
        source: place.source
      }
    end
  end
end

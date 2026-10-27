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
      places = scope
               .with_distance([@latitude, @longitude], :km)
               .order(:distance_in_km)
               .limit(@limit)
      visited_ids = @user.visits.where(place_id: places.map(&:id)).distinct.pluck(:place_id)
      places.map { |place| format(place).merge(has_visits: visited_ids.include?(place.id)) }
    end

    private

    def scope
      return base_scope.near([@latitude, @longitude], @radius, :km) if @query.length < MIN_QUERY_LENGTH

      base_scope.where('name ILIKE ?', "%#{Place.sanitize_sql_like(@query)}%")
    end

    def base_scope
      @base_scope ||= @user.places.where.not(lonlat: nil)
                           .merge(Place.map_visible(@user).or(Place.where(id: @user.visits.select(:place_id))))
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

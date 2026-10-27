# frozen_string_literal: true

module Places
  class PossibleDuplicates
    Cluster = Struct.new(:places, :survivor, :distances, keyword_init: true)

    def initialize(user:)
      @user = user
    end

    def call
      scope = user.places.not_archived
      max_radius = scope.maximum(:visit_radius)
      return [] unless max_radius

      # The constant reach lets the join use the lonlat index; the per-pair radius sum decides.
      join = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, max_radius * 2])
        INNER JOIN places other_places ON places.id < other_places.id
          AND places.user_id = other_places.user_id
          AND other_places.archived_at IS NULL
          AND ST_DWithin(places.lonlat, other_places.lonlat, ?)
          AND ST_DWithin(places.lonlat, other_places.lonlat, places.visit_radius + other_places.visit_radius)
      SQL
      pairs = scope.joins(join).pluck('places.id', 'other_places.id')
      records = ListQuery.new(user:).call.where(id: pairs.flatten.uniq).includes(:tags).index_by(&:id)
      components(pairs).map do |ids|
        places = ids.map { |id| records.fetch(id) }
        survivor = places.min_by do |place|
          curated = place.manual? || place.name_locked? || place.confirmed_visit_count.to_i.positive?
          [curated ? 0 : 1, place.created_at, place.id]
        end
        distances = places.to_h do |place|
          [place.id, Geocoder::Calculations.distance_between([survivor.lat, survivor.lon], [place.lat, place.lon],
                                                             units: :km) * 1000]
        end
        Cluster.new(places:, survivor:, distances:)
      end
    end

    private

    attr_reader :user

    def components(pairs)
      neighbours = Hash.new { |hash, id| hash[id] = [] }
      pairs.each do |first, second|
        neighbours[first] << second
        neighbours[second] << first
      end
      visited = Set.new
      neighbours.keys.filter_map do |root|
        next if visited.include?(root)

        group = []
        pending = [root]
        until pending.empty?
          id = pending.pop
          next unless visited.add?(id)

          group << id
          pending.concat(neighbours[id])
        end
        group.sort
      end
    end
  end
end

# frozen_string_literal: true

module Places
  class ListQuery
    SORTS = {
      'name' => 'places.name ASC, places.id ASC',
      'last_visit' => 'place_visit_stats.last_visited_at DESC NULLS LAST, places.name ASC, places.id ASC',
      'visit_count' => 'COALESCE(place_visit_stats.active_visit_count, 0) DESC, places.name ASC, places.id ASC'
    }.freeze

    def initialize(user:, params: {})
      @user = user
      @params = params
    end

    def call
      scope = user.places
      scope = scope.unconfirmed_for(user) if params[:filter] == 'unconfirmed'
      query = params[:q].to_s.strip
      scope = scope.where('places.name ILIKE ?', "%#{Place.sanitize_sql_like(query)}%") if query.present?
      ids = Array(params[:tag_ids]).compact_blank
      if ids.any?
        scope = scope.where(id: Tagging.where(taggable_type: 'Place', tag_id: user.tags.where(id: ids).select(:id))
                                       .select(:taggable_id))
      end
      with_statistics(scope).reorder(Arel.sql(SORTS.fetch(params[:sort].to_s, SORTS['name'])))
    end

    private

    attr_reader :user, :params

    def with_statistics(scope)
      stats = user.visits.active.where.not(place_id: nil).group(:place_id).select(
        :place_id, 'COUNT(*) AS active_visit_count', 'MAX(started_at) AS last_visited_at',
        "COUNT(*) FILTER (WHERE status = #{Visit.statuses[:confirmed]}) AS confirmed_visit_count"
      )
      scope.joins("LEFT JOIN (#{stats.to_sql}) place_visit_stats ON place_visit_stats.place_id = places.id")
           .select('places.*', 'COALESCE(place_visit_stats.active_visit_count, 0) AS active_visit_count',
                   'place_visit_stats.last_visited_at',
                   'COALESCE(place_visit_stats.confirmed_visit_count, 0) AS confirmed_visit_count')
    end
  end
end

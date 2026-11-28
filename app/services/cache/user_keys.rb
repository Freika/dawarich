# frozen_string_literal: true

module Cache
  module UserKeys
    module_function

    def countries_visited(user_id)
      "dawarich/user_#{user_id}_countries_visited"
    end

    def cities_visited(user_id)
      "dawarich/user_#{user_id}_cities_visited"
    end

    def years_tracked(user_id)
      "dawarich/user_#{user_id}_years_tracked"
    end

    def points_geocoded_stats(user_id)
      "dawarich/user_#{user_id}_points_geocoded_stats"
    end
  end
end

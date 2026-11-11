# frozen_string_literal: true

module Insights
  # The five most visited names of a year, from confirmed visits.
  class TopVisitedLocations
    LIMIT = 5

    def initialize(user, year)
      @user = user
      @year = year
    end

    def call
      name_sql = Visit.display_name_sql
      visits_in_year
        .left_joins(:place, :area)
        .group(Arel.sql(name_sql))
        .select("#{name_sql} AS display_name, COUNT(*) as visit_count, SUM(duration) as total_duration")
        .order(Arel.sql("visit_count DESC, total_duration DESC, (#{name_sql}) COLLATE \"C\" ASC"))
        .limit(LIMIT)
        .map do |visit|
          { name: visit.read_attribute(:display_name), visit_count: visit.visit_count,
            total_duration: visit.total_duration }
        end
    end

    private

    def visits_in_year
      start_time = Time.zone.local(@year, 1, 1)
      @user.scoped_visits.confirmed.where(started_at: start_time..start_time.end_of_year)
    end
  end
end

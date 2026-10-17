# frozen_string_literal: true

module Stats
  class YearCardsQuery
    def initialize(user)
      @user = user
    end

    def stats_by_year
      @stats_by_year ||= begin
        columns = %i[id year month distance updated_at user_id]
        columns << :toponyms if Geocoding::Config.for(user).enabled?

        user.scoped_stats.select(columns).order(year: :desc, updated_at: :desc).group_by(&:year)
      end
    end

    def year_distances
      @year_distances ||= stats_by_year.transform_values do |stats|
        stats_by_month = stats.index_by(&:month)

        (1..12).map do |month|
          [I18n.l(Date.new(stats.first.year, month, 1), format: :month_name), stats_by_month[month]&.distance || 0]
        end
      end
    end

    private

    attr_reader :user
  end
end

# frozen_string_literal: true

module YearlyDigests
  class YearOverYearCalculator
    def initialize(user, year)
      @user = user
      @year = year.to_i
    end

    def call
      return {} unless previous_year_stats.exists?

      {
        'previous_year' => year - 1,
        'distance_change_percent' => calculate_distance_change_percent,
        'countries_change' => calculate_countries_change,
        'cities_change' => calculate_cities_change
      }.compact
    end

    private

    attr_reader :user, :year

    def previous_year_stats
      @previous_year_stats ||= user.stats.where(year: year - 1)
    end

    def current_year_stats
      @current_year_stats ||= user.stats.where(year: year)
    end

    def calculate_distance_change_percent
      prev_distance = previous_year_stats.sum(:distance)
      return nil if prev_distance.zero?

      curr_distance = current_year_stats.sum(:distance)
      ((curr_distance - prev_distance).to_f / prev_distance * 100).round
    end

    def calculate_countries_change
      prev_count = count_countries(previous_year_stats)
      curr_count = count_countries(current_year_stats)

      curr_count - prev_count
    end

    def calculate_cities_change
      prev_count = count_cities(previous_year_stats)
      curr_count = count_cities(current_year_stats)

      curr_count - prev_count
    end

    def count_countries(stats)
      stats.flat_map do |stat|
        toponyms = stat.toponyms
        next [] unless toponyms.is_a?(Array)

        toponyms.filter_map { |t| t['country'] if t.is_a?(Hash) }
      end.uniq.compact.count
    end

    def count_cities(stats)
      stats.flat_map do |stat|
        toponyms = stat.toponyms
        next [] unless toponyms.is_a?(Array)

        toponyms.flat_map do |t|
          next [] unless t.is_a?(Hash) && t['cities'].is_a?(Array)

          t['cities'].filter_map { |c| c['city'] if c.is_a?(Hash) }
        end
      end.uniq.compact.count
    end
  end
end

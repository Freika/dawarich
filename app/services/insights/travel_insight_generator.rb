# frozen_string_literal: true

module Insights
  # Generates human-readable travel insights from time-of-day,
  # day-of-week, and seasonality data.
  class TravelInsightGenerator
    DAYS = %w[monday tuesday wednesday thursday friday saturday sunday].freeze

    MINIMUM_PERCENTAGE_THRESHOLD = 30

    def initialize(time_of_day:, day_of_week:, seasonality:)
      @time_of_day = time_of_day || {}
      @day_of_week = day_of_week || Array.new(7, 0)
      @seasonality = seasonality || {}
    end

    def call
      insights = []

      insights << time_of_day_insight
      insights << day_of_week_insight
      insights << seasonality_insight

      insights.compact!
      return nil if insights.empty?

      base_insight = I18n.t('services.insights.travel_insight_generator.sentence', insights: insights.join('. '))
      suggestion = generate_suggestion

      if suggestion
        I18n.t('services.insights.travel_insight_generator.with_suggestion', insight: base_insight,
      suggestion:)
      else
        base_insight
      end
    end

    private

    attr_reader :time_of_day, :day_of_week, :seasonality

    def time_of_day_insight
      return nil unless time_of_day.present? && time_of_day.values.any?(&:positive?)

      peak_time = time_of_day.max_by { |_, v| v.to_i }
      return nil unless peak_time && peak_time[1].to_i > MINIMUM_PERCENTAGE_THRESHOLD

      period = I18n.t("services.insights.travel_insight_generator.time_periods.#{peak_time[0]}")
      I18n.t('services.insights.travel_insight_generator.peak_time', period:)
    end

    def day_of_week_insight
      return nil unless day_of_week.present? && day_of_week.any?(&:positive?)

      weekday_total = day_of_week[0..4].sum.to_f
      weekend_total = day_of_week[5..6].sum.to_f

      weekday_avg = weekday_total / 5
      weekend_avg = weekend_total / 2

      if weekend_avg > weekday_avg * 1.3
        peak_day_idx = day_of_week.each_with_index.max_by { |v, _| v }[1]
        day = I18n.t("services.insights.travel_insight_generator.days.#{DAYS[peak_day_idx]}")
        I18n.t('services.insights.travel_insight_generator.active_day', day:)
      elsif weekday_avg > weekend_avg * 1.3
        I18n.t('services.insights.travel_insight_generator.weekday_preference')
      end
    end

    def seasonality_insight
      return nil unless seasonality.present? && seasonality.values.any?(&:positive?)

      peak_season = seasonality.max_by { |_, v| v.to_i }
      return nil unless peak_season && peak_season[1].to_i > MINIMUM_PERCENTAGE_THRESHOLD

      season = I18n.t("services.insights.travel_insight_generator.seasons.#{peak_season[0]}")
      I18n.t('services.insights.travel_insight_generator.peak_season', season:)
    end

    def generate_suggestion
      suggestions = []

      suggestions << time_based_suggestion
      suggestions << day_based_suggestion

      suggestions.compact.sample
    end

    def time_based_suggestion
      return nil if time_of_day.blank?

      peak_time = time_of_day.max_by { |_, v| v.to_i }&.first

      case peak_time
      when 'morning'
        I18n.t('services.insights.travel_insight_generator.early_start_suggestion')
      when 'evening'
        I18n.t('services.insights.travel_insight_generator.sunset_suggestion')
      end
    end

    def day_based_suggestion
      return nil unless day_of_week.present? && day_of_week.any?(&:positive?)

      weekend_total = day_of_week[5..6].sum.to_f
      weekday_total = day_of_week[0..4].sum.to_f
      weekend_avg = weekend_total / 2
      weekday_avg = weekday_total / 5

      I18n.t('services.insights.travel_insight_generator.weekend_suggestion') if weekend_avg > weekday_avg * 1.5
    end
  end
end

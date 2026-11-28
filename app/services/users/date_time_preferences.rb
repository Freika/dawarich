# frozen_string_literal: true

module Users
  class DateTimePreferences
    DATE_FORMATS = %w[auto dd.mm.yyyy dd/mm/yyyy mm/dd/yyyy yyyy-mm-dd].freeze
    TIME_FORMATS = %w[auto 12h 24h].freeze
    WEEK_STARTS = %w[monday sunday].freeze
    ALLOWED = {
      'date_format' => DATE_FORMATS, 'time_format' => TIME_FORMATS, 'first_day_of_week' => WEEK_STARTS
    }.freeze

    attr_reader :date_format, :time_format, :first_day_of_week, :cache_key

    def self.for(user)
      user&.safe_settings&.date_time_preferences || DEFAULT
    end

    def self.with(user_or_preferences, &)
      preferences = user_or_preferences.is_a?(self) ? user_or_preferences : self.for(user_or_preferences)

      Current.set(date_time_preferences: preferences, &)
    end

    def initialize(date_format: nil, time_format: nil, first_day_of_week: nil)
      @date_format = pick(DATE_FORMATS, date_format)
      @time_format = pick(TIME_FORMATS, time_format)
      @first_day_of_week = pick(WEEK_STARTS, first_day_of_week)
      @cache_key = to_h.values.join('-').freeze
      freeze
    end

    def week_start_symbol
      first_day_of_week.to_sym
    end

    def default?
      self == DEFAULT
    end

    def to_h
      { date_format:, time_format:, first_day_of_week: }
    end

    def ==(other)
      equal?(other) || (other.is_a?(self.class) && other.cache_key == cache_key)
    end
    alias eql? ==

    delegate :hash, to: :cache_key

    private

    def pick(allowed, value)
      allowed.include?(value) ? value : allowed.first
    end

    DEFAULT = new
  end
end

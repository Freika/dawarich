# frozen_string_literal: true

module DateTimePreferencesLocalization
  DATE_PRESETS = {
    'dd.mm.yyyy' => '%d.%m.%Y',
    'dd/mm/yyyy' => '%d/%m/%Y',
    'mm/dd/yyyy' => '%m/%d/%Y',
    'yyyy-mm-dd' => '%Y-%m-%d'
  }.freeze

  FORMAT_KINDS = {
    date: {
      medium: :full_date, medium_padded: :full_date, long: :full_date, default: :full_date,
      day_month_year: :full_date, day_month_year_abbreviated: :full_date, month_day_year: :full_date
    },
    time: {
      human: :full_datetime, human_with_seconds: :full_datetime_with_seconds,
      long_with_time: :full_datetime, long: :full_datetime,
      hour_minute: :time, short_with_time: :time, short: :time
    }
  }.freeze

  TIME_TOKEN = /%-?[HIl](?::|h)%M(?::%S)?(?: ?%[pP])?(?: Uhr)?/

  def localize(locale, object, format = :default, options = I18n::EMPTY_HASH)
    preferences = Current.date_time_preferences
    return super if preferences.default? || !format.is_a?(Symbol) || !object.respond_to?(:strftime)

    type = object.respond_to?(:sec) ? :time : :date
    kind = FORMAT_KINDS[type][format]
    return super unless kind

    pattern = I18n.t(:"#{type}.formats.#{format}", **options.merge(raise: true, object:, locale:))
    super(locale, object, DateTimePreferencesLocalization.pattern(pattern, kind, preferences, locale, object), options)
  end

  def self.pattern(locale_pattern, kind, preferences, locale, object)
    preset = DATE_PRESETS[preferences.date_format]

    case kind
    when :full_date
      preset || locale_pattern
    when :full_datetime, :full_datetime_with_seconds
      seconds = kind == :full_datetime_with_seconds
      return rewrite_time(locale_pattern, preferences, locale, object) unless preset

      "#{preset}, #{clock(preferences, locale, object, seconds:)}"
    else
      rewrite_time(locale_pattern, preferences, locale, object)
    end
  end

  def self.rewrite_time(locale_pattern, preferences, locale, object)
    return locale_pattern unless preferences.time_format == '12h'

    locale_pattern.gsub(TIME_TOKEN) { |token| twelve_hour_clock(locale, object, seconds: token.include?('%S')) }
  end

  def self.clock(preferences, locale, object, seconds:)
    return twelve_hour_clock(locale, object, seconds:) if preferences.time_format == '12h'

    seconds ? '%H:%M:%S' : '%H:%M'
  end

  def self.twelve_hour_clock(locale, object, seconds:)
    meridiem = I18n.t("date_time_preferences.meridiem.#{object.hour < 12 ? 'am' : 'pm'}", locale:, raise: true)
    time = seconds ? '%-I:%M:%S' : '%-I:%M'

    I18n.t('date_time_preferences.clock_12h', locale:, time:, meridiem:, raise: true)
  end
end

I18n::Backend::Simple.prepend(DateTimePreferencesLocalization)

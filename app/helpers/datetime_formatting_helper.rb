# frozen_string_literal: true

module DatetimeFormattingHelper
  def human_date(date)
    I18n.l(date.to_date, format: :day_month_year)
  end

  def human_datetime(datetime, timezone = nil)
    return unless datetime

    zoned = coerce_to_zone(datetime, timezone)

    content_tag(
      :span,
      I18n.l(zoned, format: :human),
      class: 'tooltip',
      data: { tip: zoned.iso8601 }
    )
  end

  def human_datetime_with_seconds(datetime, timezone = nil)
    return unless datetime

    zoned = coerce_to_zone(datetime, timezone)

    content_tag(
      :span,
      I18n.l(zoned, format: :human_with_seconds),
      class: 'tooltip',
      data: { tip: zoned.iso8601 }
    )
  end

  def days_left(active_until)
    return unless active_until

    time_words = distance_of_time_in_words(Time.zone.now, active_until)

    content_tag(
      :span,
      time_words,
      class: 'tooltip',
      data: { tip: I18n.t('helpers.datetime_formatting.expires_on', date: I18n.l(active_until, format: :human)) }
    )
  end

  def relative_distance_in_words(time)
    options = I18n.locale == :de ? { scope: 'datetime.distance_in_words.dative' } : {}

    time_ago_in_words(time, **options)
  end

  def format_duration_short(seconds)
    return I18n.t('units.minutes_compact', value: 0) if seconds.nil? || seconds.to_i.zero?

    total = seconds.to_i
    days = total / 86_400
    hours = (total % 86_400) / 3600
    minutes = (total % 3600) / 60

    return I18n.t('units.days_hours_compact', days:, hours:) if days.positive? && hours.positive?
    return I18n.t('units.days_compact', value: days) if days.positive?
    return I18n.t('units.hours_minutes_compact', hours:, minutes:) if hours.positive?

    I18n.t('units.minutes_compact', value: minutes)
  end

  private

  def coerce_to_zone(datetime, timezone)
    return datetime if timezone.blank?

    datetime.in_time_zone(timezone)
  rescue ArgumentError
    datetime
  end
end

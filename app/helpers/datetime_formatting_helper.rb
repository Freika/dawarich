# frozen_string_literal: true

module DatetimeFormattingHelper
  def human_date(date)
    date.strftime('%e %B %Y')
  end

  def human_datetime(datetime, timezone = nil)
    return unless datetime

    zoned = coerce_to_zone(datetime, timezone)

    content_tag(
      :span,
      zoned.strftime('%e %b %Y, %H:%M'),
      class: 'tooltip',
      data: { tip: zoned.iso8601 }
    )
  end

  def human_datetime_with_seconds(datetime, timezone = nil)
    return unless datetime

    zoned = coerce_to_zone(datetime, timezone)

    content_tag(
      :span,
      zoned.strftime('%e %b %Y, %H:%M:%S'),
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
      data: { tip: "Expires on #{active_until.iso8601}" }
    )
  end

  def format_duration_short(seconds)
    return '0m' if seconds.nil? || seconds.to_i.zero?

    total = seconds.to_i
    days = total / 86_400
    hours = (total % 86_400) / 3600
    minutes = (total % 3600) / 60

    return "#{days}d #{hours}h" if days.positive? && hours.positive?
    return "#{days}d" if days.positive?
    return "#{hours}h #{minutes}m" if hours.positive?

    "#{minutes}m"
  end

  private

  def coerce_to_zone(datetime, timezone)
    return datetime if timezone.blank?

    datetime.in_time_zone(timezone)
  rescue ArgumentError
    datetime
  end
end

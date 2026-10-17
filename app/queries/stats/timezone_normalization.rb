# frozen_string_literal: true

module Stats::TimezoneNormalization
  FALLBACK_TIMEZONE = 'Etc/UTC'

  private

  def validate_timezone(timezone)
    return FALLBACK_TIMEZONE if timezone.blank?

    tz = ActiveSupport::TimeZone[timezone]
    return tz.tzinfo.name if tz

    FALLBACK_TIMEZONE
  end
end

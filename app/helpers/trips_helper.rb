# frozen_string_literal: true

module TripsHelper
  def immich_search_url(base_url, start_date, end_date, timezone: nil)
    tz = timezone ? ActiveSupport::TimeZone[timezone] : Time.zone
    start_dt = start_date.in_time_zone(tz).to_date
    end_dt = end_date.in_time_zone(tz).to_date
    query = {
      takenAfter: "#{start_dt}T00:00:00.000Z",
      takenBefore: "#{end_dt}T23:59:59.999Z"
    }

    encoded_query = URI.encode_www_form_component(query.to_json)
    "#{base_url}/search?query=#{encoded_query}"
  end

  def photoprism_search_url(base_url, start_date, _end_date, timezone: nil)
    tz = timezone ? ActiveSupport::TimeZone[timezone] : Time.zone
    start_dt = start_date.in_time_zone(tz)
    "#{base_url}/library/browse?view=cards&year=#{start_dt.year}&month=#{start_dt.month}&order=newest&public=true&quality=3"
  end

  def photo_search_url(source, settings, start_date, end_date, timezone: nil)
    case source
    when 'immich'
      immich_search_url(settings['immich_url'], start_date, end_date, timezone:)
    when 'photoprism'
      photoprism_search_url(settings['photoprism_url'], start_date, end_date, timezone:)
    end
  end

  def trip_duration(trip)
    start_time = trip.started_at.to_time
    end_time = trip.ended_at.to_time

    # Calculate the difference
    years = end_time.year - start_time.year
    months = end_time.month - start_time.month
    days = end_time.day - start_time.day
    hours = end_time.hour - start_time.hour

    # Adjust for negative values
    if hours < 0
      hours += 24
      days -= 1
    end
    if days < 0
      prev_month = end_time.prev_month
      days += (end_time - prev_month).to_i / 1.day
      months -= 1
    end
    if months < 0
      months += 12
      years -= 1
    end

    parts = []
    parts << "#{years} year#{'s' if years != 1}" if years > 0
    parts << "#{months} month#{'s' if months != 1}" if months > 0
    parts << "#{days} day#{'s' if days != 1}" if days > 0
    parts << "#{hours} hour#{'s' if hours != 1}" if hours > 0
    parts = ["0 hours"] if parts.empty?
    parts.join(', ')
  end
end

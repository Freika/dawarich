# frozen_string_literal: true

module TripsHelper
  def immich_search_url(base_url, start_date, end_date)
    query = {
      takenAfter: "#{start_date.to_date}T00:00:00.000Z",
      takenBefore: "#{end_date.to_date}T23:59:59.999Z"
    }

    encoded_query = URI.encode_www_form_component(query.to_json)
    "#{base_url}/search?query=#{encoded_query}"
  end

  def photoprism_search_url(base_url, start_date, _end_date)
    "#{base_url}/library/browse?view=cards&year=#{start_date.year}" \
      "&month=#{start_date.month}&order=newest&public=true&quality=3"
  end

  def photo_search_url(source, settings, start_date, end_date)
    case source
    when 'immich'
      immich_search_url(settings['immich_url'], start_date, end_date)
    when 'photoprism'
      photoprism_search_url(settings['photoprism_url'], start_date, end_date)
    end
  end

  def trek_trip_url(trip)
    source = trip.trip_source
    return if source.blank? || trip.source_identifier.blank?

    "#{source.base_url.chomp('/')}/trips/#{ERB::Util.url_encode(trip.source_identifier)}"
  end

  def planned_stop_details(stop)
    time = [stop.starts_at, stop.ends_at].compact_blank.join('–').presence
    mode = planned_transport_mode(stop.transport_mode)
    duration = t('trips.source_itinerary.duration_minutes', count: stop.duration_minutes) if stop.duration_minutes
    [time, mode, stop.category.presence, duration].compact
  end

  def planned_transport_mode(mode)
    return if mode.blank?

    t("transportation_modes.#{mode}", default: mode.humanize)
  end

  def planned_reservation_status(status)
    t("trips.source_itinerary.reservation_statuses.#{status}", default: status.to_s.humanize)
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
    if hours.negative?
      hours += 24
      days -= 1
    end
    if days.negative?
      prev_month = end_time.prev_month
      days += (end_time - prev_month).to_i / 1.day
      months -= 1
    end
    if months.negative?
      months += 12
      years -= 1
    end

    parts = []
    parts << I18n.t('helpers.trips.duration.years', count: years) if years.positive?
    parts << I18n.t('helpers.trips.duration.months', count: months) if months.positive?
    parts << I18n.t('helpers.trips.duration.days', count: days) if days.positive?
    parts << I18n.t('helpers.trips.duration.hours', count: hours) if hours.positive?
    parts = [I18n.t('helpers.trips.duration.hours', count: 0)] if parts.empty?
    parts.join(', ')
  end
end

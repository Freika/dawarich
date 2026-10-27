# frozen_string_literal: true

module PlacesHelper
  def place_dwell_stats(place)
    total_minutes = place.active_visits.sum(:duration).to_i
    visit_count = place.active_visits.size
    avg_minutes = visit_count.positive? ? (total_minutes / visit_count) : 0

    {
      visit_count: visit_count,
      total_label: I18n.t('units.hours_minutes_compact', hours: total_minutes / 60, minutes: total_minutes % 60),
      avg_label: I18n.t('units.hours_minutes_compact', hours: avg_minutes / 60, minutes: avg_minutes % 60),
      primary_tag: place.tags.first,
      location_line: [place.city, place.country].compact_blank.join(', ')
    }
  end

  # Per-visit display strings used in the Place drawer's recent-visits list.
  def place_visit_time_range(visit)
    duration = visit.duration.to_i
    {
      start_label: I18n.l(visit.started_at, format: :hour_minute),
      end_label: I18n.l(visit.ended_at, format: :hour_minute),
      date_label: I18n.l(visit.started_at.to_date, format: :medium),
      duration_label: I18n.t('units.hours_minutes_compact', hours: duration / 60, minutes: duration % 60)
    }
  end

  def place_tag_text_color(color)
    hex = color.to_s.delete_prefix('#')
    hex = hex.chars.map { |char| char * 2 }.join if hex.length == 3
    channels = hex.scan(/../).map { |channel| channel.to_i(16) / 255.0 }
    luminance = channels.zip([0.2126, 0.7152, 0.0722]).sum do |channel, weight|
      linear = channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4
      linear * weight
    end
    luminance > 0.179 ? 'black' : 'white'
  end

  def merge_candidate_distance(candidate)
    unit = current_user.safe_settings.distance_unit
    value = Stat.convert_distance(candidate.distance_in_km.to_f * 1000, unit)
    I18n.t(unit == 'mi' ? 'units.miles' : 'units.kilometers', value: number_with_precision(value, precision: 2))
  end

  def place_geofence_events(place)
    return GeofenceEvent.none unless place.geofence?

    events = current_user.geofence_events.real.where(place_id: place.id)
    events = events.where(occurred_at: current_user.data_window_start..) if current_user.plan_restricted?
    events.order(occurred_at: :desc, id: :desc).limit(10)
  end

  def place_delete_confirmation(place)
    privacy_tags = place.tags.select(&:privacy_zone?).map(&:name).join(', ')
    webhooks = current_user.webhooks.where('? = ANY(place_ids)', place.id).count
    I18n.t('places.drawer.delete_consequences', visits: place.active_visits.count,
           privacy_tags: privacy_tags.presence || I18n.t('places.drawer.no_tags'), webhooks:)
  end
end

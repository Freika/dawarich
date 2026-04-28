# frozen_string_literal: true

module PlacesHelper
  # Aggregated dwell stats for the Place drawer.
  #
  # Returns a hash:
  # {
  #   visit_count: Integer,
  #   total_hours: Float (1-decimal),
  #   avg_label: 'Xh Ym',
  #   primary_tag: Tag or nil,
  #   location_line: 'City, Country' (blank parts omitted)
  # }
  def place_dwell_stats(place)
    total_minutes = place.visits.sum(:duration).to_i
    visit_count = place.visits.size
    avg_minutes = visit_count.positive? ? (total_minutes / visit_count) : 0

    {
      visit_count: visit_count,
      total_hours: (total_minutes / 60.0).round(1),
      avg_label: "#{avg_minutes / 60}h #{avg_minutes % 60}m",
      primary_tag: place.tags.first,
      location_line: [place.city, place.country].compact_blank.join(', ')
    }
  end

  # Per-visit display strings used in the Place drawer's recent-visits list.
  def place_visit_time_range(visit)
    duration = visit.duration.to_i
    {
      start_label: visit.started_at.strftime('%H:%M'),
      end_label: visit.ended_at.strftime('%H:%M'),
      date_label: visit.started_at.strftime('%Y-%m-%d'),
      duration_label: "#{duration / 60}h #{duration % 60}m"
    }
  end
end

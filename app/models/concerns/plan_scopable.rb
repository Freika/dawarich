# frozen_string_literal: true

module PlanScopable
  extend ActiveSupport::Concern

  def plan_restricted?
    !DawarichSettings.self_hosted? && lite?
  end

  def data_window_start
    DawarichSettings::LITE_DATA_WINDOW.ago
  end

  def scoped_points
    return points unless plan_restricted?

    points.where('timestamp >= ?', data_window_start.to_i)
  end

  def scoped_tracks
    return tracks unless plan_restricted?

    tracks.where('start_at >= ?', data_window_start)
  end

  def scoped_visits
    return visits unless plan_restricted?

    visits.where('started_at >= ?', data_window_start)
  end

  def scoped_stats
    return stats unless plan_restricted?

    cutoff = data_window_start
    stats.where(
      '(year > ?) OR (year = ? AND month >= ?)',
      cutoff.year, cutoff.year, cutoff.month
    )
  end
end

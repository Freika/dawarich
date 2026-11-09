# frozen_string_literal: true

module PlanScopable
  extend ActiveSupport::Concern

  delegate :effective_plan, :full_access?, :inherited_family_access?, :data_window_start, to: :entitlements

  def entitlements
    @entitlements ||= Entitlements.new(self)
  end

  def plan_restricted?
    entitlements.restricted?
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
    return visits.active unless plan_restricted?

    visits.active.where('started_at >= ?', data_window_start)
  end

  def scoped_geofence_events
    return geofence_events.real unless plan_restricted?

    geofence_events.real.where(occurred_at: data_window_start..)
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

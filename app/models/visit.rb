# frozen_string_literal: true

class Visit < ApplicationRecord
  belongs_to :area, optional: true
  belongs_to :place, optional: true
  belongs_to :user
  has_many :points, dependent: :nullify
  has_many :place_visits, dependent: :destroy
  has_many :suggested_places, through: :place_visits, source: :place

  after_commit :cleanup_old_place_if_orphan, on: :update
  after_destroy_commit :cleanup_place_if_orphan
  after_commit :bust_timeline_month_summary_cache

  validates :started_at, :ended_at, :duration, :name, :status, presence: true

  validates :ended_at, comparison: { greater_than: :started_at }

  enum :status, { suggested: 0, confirmed: 1, declined: 2 }

  def coordinates
    points.pluck(:latitude, :longitude).map { [_1[0].to_f, _1[1].to_f] }
  end

  def default_name
    name || area&.name || place&.name
  end

  # in meters
  def default_radius
    return area&.radius if area.present?

    radius = points.map do |point|
      Geocoder::Calculations.distance_between(
        center, [point.lat, point.lon], units: user.safe_settings.distance_unit.to_sym
      )
    end.max

    radius && radius >= 15 ? radius : 15
  end

  def center
    if area.present?
      [area.lat, area.lon]
    elsif place.present?
      [place.lat, place.lon]
    else
      center_from_points
    end
  end

  private

  def center_from_points
    return [0, 0] if points.empty?

    lat_sum = points.sum(&:lat)
    lon_sum = points.sum(&:lon)
    count = points.size.to_f

    [lat_sum / count, lon_sum / count]
  end

  def cleanup_old_place_if_orphan
    old_id, = previous_changes['place_id']
    return unless old_id

    Places::DeleteIfOrphanJob.perform_later(old_id)
  end

  def cleanup_place_if_orphan
    return unless place_id

    Places::DeleteIfOrphanJob.perform_later(place_id)
  end

  # Keeps the Timeline calendar/filter-count cache fresh when visits are
  # created or changed by ANY path — background import/detection jobs as well
  # as the controller. Without this, MonthSummary (cached 5 min) serves stale
  # status_counts right after a visit is auto-detected, so the FILTER pills
  # read 0 until the user happens to act. Busts both the old and new month so
  # edits that move a visit across a month boundary clear both.
  def bust_timeline_month_summary_cache
    return unless user

    tz = user.safe_settings.timezone.presence || 'UTC'
    times = [started_at]
    times << saved_change_to_started_at&.first if saved_change_to_started_at?

    Time.use_zone(tz) do
      times.compact.map { |t| t.in_time_zone.to_date.beginning_of_month }.uniq.each do |month_start|
        Rails.cache.delete(Timeline::MonthSummary.cache_key_for(user, month_start))
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[Visit##{id}] timeline month cache bust failed: #{e.class}: #{e.message}")
  end
end

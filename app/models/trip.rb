# frozen_string_literal: true

class Trip < ApplicationRecord
  include Demoable
  include Calculateable
  include DistanceConvertible
  include Notable

  RECALCULATE_COOLDOWN = 60.seconds
  # A stamped point reads its device from point_sources exclusively; the
  # legacy column serves unstamped rows (see PointDimensionReads).
  DEVICE_SQL = 'COALESCE(CASE WHEN points.source_id IS NULL THEN points.tracker_id ' \
               "ELSE point_sources.tracker_id END, '')"

  DAY_ENDPOINT_COLUMNS = [
    'ST_XMin(ST_Extent(points.lonlat::geometry))', 'ST_YMin(ST_Extent(points.lonlat::geometry))',
    'ST_XMax(ST_Extent(points.lonlat::geometry))', 'ST_YMax(ST_Extent(points.lonlat::geometry))',
    '(ARRAY_AGG(ST_X(points.lonlat::geometry) ORDER BY points.timestamp))[1]',
    '(ARRAY_AGG(ST_Y(points.lonlat::geometry) ORDER BY points.timestamp))[1]',
    '(ARRAY_AGG(ST_X(points.lonlat::geometry) ORDER BY points.timestamp DESC))[1]',
    '(ARRAY_AGG(ST_Y(points.lonlat::geometry) ORDER BY points.timestamp DESC))[1]'
  ].map { |column| Arel.sql(column) }.freeze

  has_rich_text :description

  belongs_to :user
  belongs_to :trip_source, optional: true
  has_many :shared_links, -> { where(resource_type: SharedLink.resource_types[:trip]) },
           foreign_key: :resource_id, inverse_of: false, dependent: :destroy
  has_many :planned_days, -> { order(:date) }, dependent: :destroy, inverse_of: :trip
  has_many :planned_reservations, dependent: :destroy
  has_many :planned_accommodations, dependent: :destroy
  has_many :planned_travellers, dependent: :destroy
  has_many :planned_unplanned_places, -> { order(:position) }, dependent: :destroy, inverse_of: :trip

  enum :source_status, { active: 0, stopped: 1 }, prefix: :source

  validates :name, :started_at, :ended_at, presence: true
  validate :started_at_before_ended_at

  attr_accessor :skip_calculation_enqueue

  scope :with_route_summary, lambda {
    select(
      *(column_names - ['path']).map { |column| arel_table[column] },
      Arel.sql('trips.path IS NOT NULL AS route_present'),
      Arel.sql('ST_XMin(trips.path) AS route_min_lon'), Arel.sql('ST_YMin(trips.path) AS route_min_lat'),
      Arel.sql('ST_XMax(trips.path) AS route_max_lon'), Arel.sql('ST_YMax(trips.path) AS route_max_lat')
    )
  }

  def route_present?
    return self[:route_present] if has_attribute?(:route_present)

    path.present?
  end

  def route_bounds
    return unless route_present?

    if has_attribute?(:route_min_lon)
      [[self[:route_min_lon], self[:route_min_lat]], [self[:route_max_lon], self[:route_max_lat]]].map do |pair|
        pair.map(&:to_f)
      end
    else
      xs = path.points.map(&:x)
      ys = path.points.map(&:y)
      [[xs.min, ys.min], [xs.max, ys.max]]
    end
  end

  after_create :enqueue_calculation_jobs, if: :should_enqueue_calculation_jobs?
  after_update :enqueue_calculation_jobs, if: :should_recalculate_after_update?

  def enqueue_calculation_jobs
    Trips::CalculateAllJob.perform_later(id, user.safe_settings.distance_unit)
  end

  def calculation_missing?
    !route_present? || distance.blank?
  end

  def source_imported?
    source_identifier.present?
  end

  def recalculating?
    last_recalculated_at.present? && last_recalculated_at > RECALCULATE_COOLDOWN.ago
  end

  def points
    user.points.not_anomaly.where(timestamp: started_at.to_i..ended_at.to_i).order(:timestamp)
  end

  def primary_device_windows
    @primary_device_windows ||= build_primary_device_windows
  end

  def cached_primary_device_windows
    recording_devices[:windows]
  end

  def multiple_recording_devices?
    recording_devices[:multiple]
  end

  def recording_devices_cache_key
    @recording_devices_cache_key ||= begin
      range = { start_at: started_at.to_i, end_at: ended_at.to_i }
      ['trip_recording_devices/v3', id, started_at.to_i, ended_at.to_i,
       Points::Revision.for_user(user_id, **range), Tracks::Revision.for_user(user_id, **range),
       user.safe_settings.minutes_between_routes]
    end
  end

  def plan_geojson
    Trips::PlanGeojson.new(self).call
  end

  def day_stats(timezone, points_scope: primary_device_points)
    day_expr = "(to_timestamp(points.timestamp) AT TIME ZONE #{self.class.connection.quote(timezone)})::date"
    rows = points_scope.reorder(nil).group(Arel.sql(day_expr)).pluck(
      Arel.sql(day_expr),
      Arel.sql('MIN(points.timestamp)'),
      Arel.sql('MAX(points.timestamp)'),
      Arel.sql('COALESCE(ST_Length(ST_MakeLine(points.lonlat::geometry ORDER BY points.timestamp)::geography), 0)'),
      *DAY_ENDPOINT_COLUMNS
    )

    rows.each_with_object({}) do |(day, first_ts, last_ts, distance_m, *geometry), stats|
      stats[day] = {
        first_time: Time.at(first_ts).in_time_zone(timezone),
        last_time: Time.at(last_ts).in_time_zone(timezone),
        distance_m: distance_m.to_f
      }.merge(day_geometry(geometry))
    end
  end

  def plan_scoped_route_points
    user.plan_restricted? ? primary_device_points.merge(user.scoped_points) : primary_device_points
  end

  def primary_device_points
    scope = points.left_joins(:source)
    return scope unless multiple_recording_devices?

    windows = cached_primary_device_windows.map do |window|
      self.class.sanitize_sql_array(['(?, ?::bigint, ?::bigint)',
                                     window[:tracker_id], window[:start_at], window[:end_at]])
    end
    scope.where(<<~SQL.squish)
      EXISTS (
        SELECT 1 FROM (VALUES #{windows.join(', ')}) AS recording_windows(tracker_id, start_at, end_at)
        WHERE recording_windows.tracker_id = #{DEVICE_SQL}
          AND points.timestamp BETWEEN recording_windows.start_at AND recording_windows.end_at
      )
    SQL
  end

  def photo_previews
    @photo_previews ||= select_dominant_orientation(photos).sample(12)
  end

  def photo_sources
    @photo_sources ||= photos.map { _1[:source] }.uniq
  end

  def photos_by_day(timezone)
    zone = Time.find_zone(timezone) || Time.find_zone('UTC')

    photos.each_with_object({}) do |photo, acc|
      date = parse_photo_date(photo[:taken_at], zone)
      next if date.nil?

      (acc[date] ||= []) << photo
    end
  end

  def calculate_countries
    self.visited_countries = points.not_flyover.pluck(:country_name).uniq.compact
  end

  private

  def build_primary_device_windows
    events = device_windows.each_with_index.flat_map do |(_, first, last), priority|
      [[first, priority, true], [last + 1, priority, false]]
    end.group_by(&:first).sort
    active = []
    windows = []

    events.each_cons(2) do |(timestamp, changes), (next_timestamp, _)|
      changes.each do |_, priority, starting|
        if starting
          index = active.bsearch_index { |existing| existing > priority } || active.size
          active.insert(index, priority)
        else
          active.delete(priority)
        end
      end
      append_device_window(windows, active.first, timestamp, next_timestamp - 1) if active.any?
    end
    windows
  end

  def append_device_window(windows, priority, start_at, end_at)
    tracker_id = device_windows[priority].first
    previous = windows.last
    if previous && previous[:tracker_id] == tracker_id && previous[:end_at] + 1 == start_at
      previous[:end_at] = end_at
    else
      windows << { tracker_id:, start_at:, end_at: }
    end
  end

  def recording_devices
    @recording_devices ||= Rails.cache.fetch(recording_devices_cache_key, expires_in: 1.hour) do
      { windows: primary_device_windows, multiple: device_windows.map(&:first).uniq.size > 1 }
    end
  end

  def day_geometry(values)
    min_lon, min_lat, max_lon, max_lat, first_lon, first_lat, last_lon, last_lat = values.map(&:to_f)
    {
      bounds: [[min_lon, min_lat], [max_lon, max_lat]],
      first_coordinates: [first_lon, first_lat],
      last_coordinates: [last_lon, last_lat]
    }
  end

  def device_windows
    @device_windows ||= begin
      scope = points.reorder(nil).left_joins(:source)
                    .select("points.id, points.timestamp, #{DEVICE_SQL} AS tracker_id")
      gap_seconds = user.safe_settings.minutes_between_routes * 60

      self.class.connection.select_rows(<<~SQL.squish)
        WITH ordered_points AS (
          SELECT id, timestamp, tracker_id,
            LAG(timestamp) OVER (PARTITION BY tracker_id ORDER BY timestamp, id) AS previous_timestamp
          FROM (#{scope.to_sql}) AS recordings
        ), sessions AS (
          SELECT timestamp, tracker_id,
            SUM(CASE WHEN previous_timestamp IS NULL OR timestamp - previous_timestamp > #{gap_seconds}
                     THEN 1 ELSE 0 END)
              OVER (PARTITION BY tracker_id ORDER BY timestamp, id ROWS UNBOUNDED PRECEDING) AS session_number
          FROM ordered_points
        )
        SELECT tracker_id, MIN(timestamp), MAX(timestamp)
        FROM sessions
        GROUP BY tracker_id, session_number
        ORDER BY SUM(COUNT(*)) OVER (PARTITION BY tracker_id) DESC,
                 NULLIF(tracker_id, '') NULLS LAST, MIN(timestamp)
      SQL
    end
  end

  def path_coordinates
    primary_device_points.pluck(:lonlat)
  end

  def calculate_distance_from_coordinates
    Point.total_distance(primary_device_points, :m)
  end

  def should_recalculate_after_update?
    return false if demo? || skip_calculation_enqueue

    saved_change_to_started_at? || saved_change_to_ended_at?
  end

  def should_enqueue_calculation_jobs?
    !demo? && !skip_calculation_enqueue
  end

  def photos
    @photos ||= Trips::Photos.new(self, user).call
  end

  def parse_photo_date(raw, zone)
    return nil if raw.blank?

    zone.parse(raw.to_s)&.to_date
  rescue ArgumentError, TypeError
    nil
  end

  def select_dominant_orientation(photos)
    vertical_photos = photos.select { |photo| photo[:orientation] == 'portrait' }
    horizontal_photos = photos.select { |photo| photo[:orientation] == 'landscape' }

    # this is ridiculous, but I couldn't find my way around frontend
    # to show all photos in the same height
    vertical_photos.count > horizontal_photos.count ? vertical_photos : horizontal_photos
  end

  def started_at_before_ended_at
    return if started_at.blank? || ended_at.blank?
    return unless started_at >= ended_at

    errors.add(:ended_at, I18n.t('models.trip.must_be_after_start_date'))
  end
end

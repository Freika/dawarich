# frozen_string_literal: true

class Trip < ApplicationRecord
  include Demoable
  include Calculateable
  include DistanceConvertible
  include Notable

  RECALCULATE_COOLDOWN = 60.seconds
  # A stamped point reads its device from point_sources exclusively; the
  # legacy column serves unstamped rows (see PointDimensionReads).
  DEVICE_SQL = 'CASE WHEN points.source_id IS NULL THEN points.tracker_id ELSE point_sources.tracker_id END'

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

  after_create :enqueue_calculation_jobs, if: :should_enqueue_calculation_jobs?
  after_update :enqueue_calculation_jobs, if: :should_recalculate_after_update?

  def enqueue_calculation_jobs
    Trips::CalculateAllJob.perform_later(id, user.safe_settings.distance_unit)
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

  # Devices recording at the same time are separate paths, so the trip line,
  # its distance and its day routes follow the device with the most points.
  def primary_tracker_id
    return @primary_tracker_id if defined?(@primary_tracker_id)

    @primary_tracker_id = points.reorder(nil).left_joins(:source)
                                .group(Arel.sql(DEVICE_SQL))
                                .order(Arel.sql('COUNT(*) DESC'), Arel.sql("#{DEVICE_SQL} NULLS LAST"))
                                .pick(Arel.sql(DEVICE_SQL))
  end

  def plan_geojson
    Trips::PlanGeojson.new(self).call
  end

  def day_stats(timezone)
    day_expr = "(to_timestamp(points.timestamp) AT TIME ZONE #{self.class.connection.quote(timezone)})::date"
    rows = primary_device_points.reorder(nil).group(Arel.sql(day_expr)).pluck(
      Arel.sql(day_expr),
      Arel.sql('MIN(points.timestamp)'),
      Arel.sql('MAX(points.timestamp)'),
      Arel.sql('COALESCE(ST_Length(ST_MakeLine(points.lonlat::geometry ORDER BY points.timestamp)::geography), 0)')
    )

    rows.each_with_object({}) do |(day, first_ts, last_ts, distance_m), stats|
      stats[day] = {
        first_time: Time.at(first_ts).in_time_zone(timezone),
        last_time: Time.at(last_ts).in_time_zone(timezone),
        distance_m: distance_m.to_f
      }
    end
  end

  def primary_device_points
    scope = points.left_joins(:source)
    tracker_id = primary_tracker_id
    return scope.where("(#{DEVICE_SQL}) IS NULL") if tracker_id.nil?

    scope.where("(#{DEVICE_SQL}) = ?", tracker_id)
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
    self.visited_countries = points.pluck(:country_name).uniq.compact
  end

  private

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

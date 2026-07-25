# frozen_string_literal: true

class Places::Visits::Create
  attr_reader :user, :places

  # Default radius for place visit detection (in meters)
  DEFAULT_PLACE_RADIUS = 100.0

  def self.default_throttle_seconds
    ENV.fetch('PLACE_VISITS_THROTTLE_SECONDS', '0.1').to_f
  end

  def initialize(user, places, throttle_seconds: self.class.default_throttle_seconds, sleep_fn: method(:sleep))
    @user = user
    @places = places
    @throttle_seconds = throttle_seconds
    @sleep_fn = sleep_fn
    @time_threshold_minutes = user.safe_settings.time_threshold_minutes || 30
    @merge_threshold_minutes = user.safe_settings.merge_threshold_minutes || 15
  end

  def call
    places.each do |place|
      throttle if place_visits(place)
    end
  end

  private

  def place_visits(place)
    months = distinct_months_for_place(place)
    Rails.logger.debug(
      '[Places::Visits::Create] distinct_months_for_place ' \
        "place_id=#{place.id} months=#{months.inspect} count=#{months.size}"
    )

    months.each do |month|
      points = place_points_for_month(place, month)
      visits = Visits::Group.new(
        time_threshold_minutes: @time_threshold_minutes,
        merge_threshold_minutes: @merge_threshold_minutes
      ).call(points, already_sorted: true)

      visits.each do |time_range, visit_points|
        create_or_update_visit(place, time_range, visit_points)
      end
    end

    cleanup_orphaned_visits(place) if months.any?

    months.any?
  end

  def cleanup_orphaned_visits(place)
    Visit.where(place_id: place.id, user_id: user.id, status: :suggested)
         .where.missing(:points)
         .destroy_all
  end

  def throttle
    @sleep_fn.call(@throttle_seconds) if @throttle_seconds.positive?
  end

  def distinct_months_for_place(place)
    place_radius = DEFAULT_PLACE_RADIUS.to_f / ::DISTANCE_UNITS[user.safe_settings.distance_unit.to_sym]

    relation = Point.where(user_id: user.id)
                    .where(visit_id: nil)
                    .near([place.latitude, place.longitude], place_radius, user.safe_settings.distance_unit)
    sql = <<~SQL.squish
      SELECT DISTINCT TO_CHAR(TO_TIMESTAMP(timestamp), 'YYYY-MM') AS month
      FROM (#{relation.to_sql}) AS sub
      ORDER BY month ASC
    SQL
    result = ActiveRecord::Base.connection.select_all(sql)
    result.map { |r| r['month'] }
  end

  def place_points_for_month(place, month)
    place_radius = DEFAULT_PLACE_RADIUS.to_f / ::DISTANCE_UNITS[user.safe_settings.distance_unit.to_sym]

    year, month_num = month.split('-').map(&:to_i)
    month_start = Time.utc(year, month_num, 1).to_i
    month_end = (Time.utc(year, month_num, 1) + 1.month).to_i - 1

    editable_visit_ids = Visit.where(place_id: place.id, user_id: user.id, status: :suggested).pluck(:id)

    Point.where(user_id: user.id)
         .without_raw_data
         .near([place.latitude, place.longitude], place_radius, user.safe_settings.distance_unit)
         .where(timestamp: month_start..month_end)
         .where(visit_id: [nil, *editable_visit_ids])
         .order(timestamp: :asc)
         .to_a
  end

  def create_or_update_visit(place, time_range, visit_points)
    Rails.logger.info("Visit from #{time_range}, Points: #{visit_points.size}")

    ActiveRecord::Base.transaction do
      current_place = Place.lock.find_by(id: place.id)
      next unless current_place

      visit = find_or_initialize_visit(current_place.id, visit_points.first.timestamp)

      visit.tap do |v|
        v.ended_at = Time.zone.at(visit_points.last.timestamp)
        v.duration = (visit_points.last.timestamp - visit_points.first.timestamp) / 60
        if v.new_record?
          v.name = "#{current_place.name}, #{time_range}"
          v.status = :suggested
        end
      end

      visit.save!

      Point.where(id: visit_points.map(&:id)).update_all(visit_id: visit.id)
    end
  end

  def find_or_initialize_visit(place_id, timestamp)
    Visit.find_or_initialize_by(
      place_id:,
      user_id: user.id,
      started_at: Time.zone.at(timestamp)
    )
  end
end

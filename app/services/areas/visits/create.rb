# frozen_string_literal: true

class Areas::Visits::Create
  attr_reader :user, :areas

  def initialize(user, areas)
    @user = user
    @areas = areas
    @time_threshold_minutes = 30 || user.safe_settings.time_threshold_minutes
    @merge_threshold_minutes = 15 || user.safe_settings.merge_threshold_minutes
  end

  def call
    # Don't return unnecessary values, causes high memory usage (see #2119)
    areas.each { area_visits(_1) }
  end

  private

  def area_visits(area)
    # Process month-by-month sequentially to avoid loading all points into memory.
    # Loading all points and grouping in Ruby caused 16GB+ memory usage (see #2119).
    # Query distinct months first (no point data), then process each month separately.
    # Process visits immediately per month - DO NOT build a hash of all visits for all months
    # before processing (removing that intermediate hash was a key optimization).
    months = distinct_months_for_area(area)
    Rails.logger.debug("[Areas::Visits::Create] distinct_months_for_area area_id=#{area.id} months=#{months.inspect} count=#{months.size}")

    months.each do |month|
      points = area_points_for_month(area, month)
      visits = Visits::Group.new(
        time_threshold_minutes: @time_threshold_minutes,
        merge_threshold_minutes: @merge_threshold_minutes
      ).call(points, already_sorted: true)

      visits.each do |time_range, visit_points|
        create_or_update_visit(area, time_range, visit_points)
      end
    end
  end

  def distinct_months_for_area(area)
    area_radius =
      if user.safe_settings.distance_unit == :km
        area.radius / ::DISTANCE_UNITS[:km]
      else
        area.radius / ::DISTANCE_UNITS[user.safe_settings.distance_unit.to_sym]
      end

    # Same pattern as User#years_tracked: Use select_all for better performance with large datasets.
    # From the subquery (filtered points, runs db-side), compute distinct month strings.
    relation = Point.where(user_id: user.id)
                    .near([area.latitude, area.longitude], area_radius, user.safe_settings.distance_unit)
    sql = <<~SQL.squish
      SELECT DISTINCT TO_CHAR(TO_TIMESTAMP(timestamp), 'YYYY-MM') AS month
      FROM (#{relation.to_sql}) AS sub
      ORDER BY month ASC
    SQL
    result = ActiveRecord::Base.connection.select_all(sql)
    result.map { |r| r['month'] }
  end

  def area_points_for_month(area, month)
    area_radius =
      if user.safe_settings.distance_unit == :km
        area.radius / ::DISTANCE_UNITS[:km]
      else
        area.radius / ::DISTANCE_UNITS[user.safe_settings.distance_unit.to_sym]
      end

    year, month_num = month.split('-').map(&:to_i)
    month_start = Time.utc(year, month_num, 1).to_i
    month_end = (Time.utc(year, month_num, 1) + 1.month).to_i - 1

    Point.where(user_id: user.id)
         # Drop raw_data JSON to keep memory usage reasonable (see #2119)
         .without_raw_data
         .near([area.latitude, area.longitude], area_radius, user.safe_settings.distance_unit)
         .where(timestamp: month_start..month_end)
         .order(timestamp: :asc)
         .to_a
  end

  def create_or_update_visit(area, time_range, visit_points)
    Rails.logger.info("Visit from #{time_range}, Points: #{visit_points.size}")

    ActiveRecord::Base.transaction do
      visit = find_or_initialize_visit(area.id, visit_points.first.timestamp)

      visit.tap do |v|
        v.name = "#{area.name}, #{time_range}"
        v.ended_at = Time.zone.at(visit_points.last.timestamp)
        v.duration = (visit_points.last.timestamp - visit_points.first.timestamp) / 60
        v.status = :suggested
      end

      visit.save!

      visit_points.each { _1.update!(visit_id: visit.id) }
    end
  end

  def find_or_initialize_visit(area_id, timestamp)
    Visit.find_or_initialize_by(
      area_id:,
      user_id: user.id,
      started_at: Time.zone.at(timestamp)
    )
  end
end

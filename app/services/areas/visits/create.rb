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
    areas.map { area_visits(_1) }
  end

  private

  def area_visits(area)
    points_grouped_by_month = area_points(area)
    visits_by_month = group_points_by_month(points_grouped_by_month)

    visits_by_month.each do |month, visits|
      Rails.logger.info("Month: #{month}, Total visits: #{visits.size}")

      visits.each do |time_range, visit_points|
        create_or_update_visit(area, time_range, visit_points)
      end
    end
  end

  def area_points(area)
    area_radius =
      if ::DISTANCE_UNIT == :km
        area.radius / 1000.0
      else
        area.radius / 1609.344
      end

    points = Point.where(user_id: user.id)
                  .near([area.latitude, area.longitude], area_radius, DISTANCE_UNIT)
                  .order(timestamp: :asc)

    # check if all points within the area are assigned to a visit

    points.group_by { |point| Time.zone.at(point.timestamp).strftime('%Y-%m') }
  end

  def group_points_by_month(points)
    visits_by_month = {}

    points.each do |month, points_in_month|
      visits_by_month[month] = Visits::Group.new(
        time_threshold_minutes: @time_threshold_minutes,
        merge_threshold_minutes: @merge_threshold_minutes
      ).call(points_in_month)
    end

    visits_by_month
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

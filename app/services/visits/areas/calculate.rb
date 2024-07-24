# frozen_string_literal: true

class Visits::Areas::Calculate
  attr_reader :user, :areas

  def initialize(user, areas)
    @user = user
    @areas = areas
    @time_threshold_minutes = 30 || user.settings['time_threshold_minutes']
    @merge_threshold_minutes = 15 || user.settings['merge_threshold_minutes']
  end

  def call
    areas.map { area_visits(_1) }
  end

  private

  def area_visits(area)
    points_grouped_by_month = area_points(area)
    visits_by_month = {}

    points_grouped_by_month.each do |month, points_in_month|
      visits_by_month[month] = Visits::Group.new(
        time_threshold_minutes: @time_threshold_minutes,
        merge_threshold_minutes: @merge_threshold_minutes
      ).call(points_in_month)
    end

    visits_by_month.each do |month, visits|
      Rails.logger.info("Month: #{month}, Total visits: #{visits.size}")

      visits.each do |time_range, visit_points|
        Rails.logger.info("Visit from #{time_range}, Points: #{visit_points.size}")

        ActiveRecord::Base.transaction do
          visit = Visit.find_or_initialize_by(
            area_id: area.id,
            user_id: user.id,
            started_at: Time.zone.at(visit_points.first.timestamp)
          )

          visit.update!(
            name: "#{area.name}, #{time_range}",
            area_id: area.id,
            user_id: user.id,
            started_at: Time.zone.at(visit_points.first.timestamp),
            ended_at: Time.zone.at(visit_points.last.timestamp),
            duration: (visit_points.last.timestamp - visit_points.first.timestamp) / 60, # in minutes
            status: :pending
          )

          visit_points.each { _1.update!(visit_id: visit.id) }
        end
      end
    end
  end

  def area_points(area)
    area_radius_in_km = area.radius / 1000.0

    Point.where(user_id: user.id)
         .near([area.latitude, area.longitude], area_radius_in_km)
         .order(timestamp: :asc)
         .group_by { |point| Time.zone.at(point.timestamp).strftime('%Y-%m') }
  end
end

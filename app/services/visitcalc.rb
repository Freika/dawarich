# frozen_string_literal: true

class Visitcalc
  class Visit
    attr_accessor :start_time, :end_time, :points

    def initialize(start_time)
      @start_time = start_time
      @end_time = start_time
      @points = []
    end

    def add_point(point)
      @points << point
      @end_time = point.timestamp if point.timestamp > @end_time
    end

    def duration_in_minutes
      (end_time - start_time) / 60.0
    end

    def valid?
      @points.size > 1 && duration_in_minutes >= 10
    end
  end

  def call
    # Usage
    area = Area.last
    points = Point.near([area.latitude, area.longitude], (area.radius / 1000.0)).order(timestamp: :asc)
    points_grouped_by_month = points.group_by { |point| Time.zone.at(point.timestamp).strftime('%Y-%m') }

    visits_by_month = {}
    points_grouped_by_month.each do |month, points_in_month|
      visits_by_month[month] = group_points_into_visits(points_in_month, 30, 15)
    end

    # Debugging output to check the number of visits and some sample data
    visits_by_month.each do |month, visits|
      puts "Month: #{month}, Total visits: #{visits.size}"
      visits.each do |time_range, visit_points|
        puts "Visit from #{time_range}, Points: #{visit_points.size}"
      end
    end

    visits_by_month.map { |d, v| v.keys }
  end

  def group_points_into_visits(points, time_threshold_minutes = 30, merge_threshold_minutes = 15)
    # Ensure points are sorted by timestamp
    sorted_points = points.sort_by(&:timestamp)
    visits = []
    current_visit = nil

    sorted_points.each do |point|
      point_time = point.timestamp
      puts "Processing point at #{Time.zone.at(point_time).strftime('%Y-%m-%d %H:%M:%S')}"
      if current_visit.nil?
        puts "Starting new visit at #{Time.zone.at(point_time).strftime('%Y-%m-%d %H:%M:%S')}"
        current_visit = Visit.new(point_time)
        current_visit.add_point(point)
      else
        time_difference = (point_time - current_visit.end_time) / 60.0 # Convert to minutes
        puts "Time difference: #{time_difference.round} minutes"

        if time_difference <= time_threshold_minutes
          current_visit.add_point(point)
        else
          if current_visit.valid?
            puts "Ending visit from #{Time.zone.at(current_visit.start_time).strftime('%Y-%m-%d %H:%M:%S')} to #{Time.zone.at(current_visit.end_time).strftime('%Y-%m-%d %H:%M:%S')}, duration: #{current_visit.duration_in_minutes} minutes, points: #{current_visit.points.size}"
            visits << current_visit
          else
            puts "Discarding visit from #{Time.zone.at(current_visit.start_time).strftime('%Y-%m-%d %H:%M:%S')} to #{Time.zone.at(current_visit.end_time).strftime('%Y-%m-%d %H:%M:%S')} (invalid, points: #{current_visit.points.size}, duration: #{current_visit.duration_in_minutes} minutes)"
          end
          current_visit = Visit.new(point_time)
          current_visit.add_point(point)
          puts "Starting new visit at #{Time.zone.at(point_time).strftime('%Y-%m-%d %H:%M:%S')}"
        end
      end
    end

    # Add the last visit to the list if it is valid
    if current_visit&.valid?
      puts "Ending visit from #{Time.zone.at(current_visit.start_time).strftime('%Y-%m-%d %H:%M:%S')} to #{Time.zone.at(current_visit.end_time).strftime('%Y-%m-%d %H:%M:%S')}, duration: #{current_visit.duration_in_minutes} minutes, points: #{current_visit.points.size}"
      visits << current_visit
    else
      puts "Discarding last visit from #{Time.zone.at(current_visit.start_time).strftime('%Y-%m-%d %H:%M:%S')} to #{Time.zone.at(current_visit.end_time).strftime('%Y-%m-%d %H:%M:%S')} (invalid, points: #{current_visit.points.size}, duration: #{current_visit.duration_in_minutes} minutes)"
    end

    # Merge visits that are not more than merge_threshold_minutes apart
    merged_visits = []
    previous_visit = nil

    visits.each do |visit|
      if previous_visit.nil?
        previous_visit = visit
      else
        time_difference = (visit.start_time - previous_visit.end_time) / 60.0 # Convert to minutes
        if time_difference <= merge_threshold_minutes
          previous_visit.points.concat(visit.points)
          previous_visit.end_time = visit.end_time
        else
          merged_visits << previous_visit
          previous_visit = visit
        end
      end
    end

    merged_visits << previous_visit if previous_visit

    # Sort visits by start time
    merged_visits.sort_by!(&:start_time)

    # Convert visits to a hash with human-readable datetime ranges as keys and points as values
    visits_hash = {}
    merged_visits.each do |visit|
      start_time_str = Time.zone.at(visit.start_time).strftime('%Y-%m-%d %H:%M:%S')
      end_time_str = Time.zone.at(visit.end_time).strftime('%Y-%m-%d %H:%M:%S')
      visits_hash["#{start_time_str} - #{end_time_str}"] = visit.points
    end

    visits_hash
  end
end

# Run the Visitcalc class
# Visitcalc.new.call

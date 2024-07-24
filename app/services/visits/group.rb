# frozen_string_literal: true

class Visits::Group
  def initialize(time_threshold_minutes: 30, merge_threshold_minutes: 15)
    @time_threshold_minutes = time_threshold_minutes
    @merge_threshold_minutes = merge_threshold_minutes
    @visits = []
    @current_visit = nil
  end

  def call(points)
    process_points(points.sort_by(&:timestamp))
    finalize_current_visit
    merge_visits
    convert_to_hash
  end

  private

  def process_points(sorted_points)
    sorted_points.each { process_point(_1) }
  end

  def process_point(point)
    point_time = point.timestamp
    log_point_processing(point_time)

    @current_visit.nil? ? start_new_visit(point_time, point) : handle_existing_visit(point_time, point)
  end

  def start_new_visit(point_time, point)
    log_new_visit(point_time)

    @current_visit = VisitDraft.new(point_time)
    @current_visit.add_point(point)
  end

  def handle_existing_visit(point_time, point)
    time_difference = calculate_time_difference(point_time)
    log_time_difference(time_difference)

    if time_difference <= @time_threshold_minutes
      @current_visit.add_point(point)
    else
      finalize_current_visit
      start_new_visit(point_time, point)
    end
  end

  def calculate_time_difference(point_time)
    (point_time - @current_visit.end_time) / 60.0
  end

  def finalize_current_visit
    return if @current_visit.nil?

    if @current_visit.valid?
      log_valid_visit
      @visits << @current_visit
    else
      log_invalid_visit
    end

    @current_visit = nil
  end

  def merge_visits
    merged_visits = []
    previous_visit = nil

    @visits.each do |visit|
      if previous_visit.nil?
        previous_visit = visit
      else
        time_difference = (visit.start_time - previous_visit.end_time) / 60.0
        if time_difference <= @merge_threshold_minutes
          merge_visit(previous_visit, visit)
        else
          merged_visits << previous_visit
          previous_visit = visit
        end
      end
    end

    merged_visits << previous_visit if previous_visit
    @visits = merged_visits.sort_by(&:start_time)
  end

  def merge_visit(previous_visit, current_visit)
    previous_visit.points.concat(current_visit.points)
    previous_visit.end_time = current_visit.end_time
  end

  def convert_to_hash
    @visits.each_with_object({}) do |visit, hash|
      hash[format_time_range(visit)] = visit.points
    end
  end

  def format_time_range(visit)
    start_time = format_time(visit.start_time)
    end_time = format_time(visit.end_time)
    "#{start_time} - #{end_time}"
  end

  def format_time(timestamp)
    Time.zone.at(timestamp).strftime('%Y-%m-%d %H:%M')
  end

  def log_point_processing(point_time)
    Rails.logger.info("Processing point at #{format_time(point_time)}")
  end

  def log_new_visit(point_time)
    Rails.logger.info("Starting new visit at #{format_time(point_time)}")
  end

  def log_time_difference(time_difference)
    Rails.logger.info("Time difference: #{time_difference.round} minutes")
  end

  def log_valid_visit
    Rails.logger.info("Ending visit from #{format_time(@current_visit.start_time)} to #{format_time(@current_visit.end_time)}, duration: #{@current_visit.duration_in_minutes} minutes, points: #{@current_visit.points.size}") # rubocop:disable Layout/LineLength
  end

  def log_invalid_visit
    Rails.logger.info("Discarding visit from #{format_time(@current_visit.start_time)} to #{format_time(@current_visit.end_time)} (invalid, points: #{@current_visit.points.size}, duration: #{@current_visit.duration_in_minutes} minutes)") # rubocop:disable Layout/LineLength
  end
end

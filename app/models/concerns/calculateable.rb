# frozen_string_literal: true

module Calculateable
  extend ActiveSupport::Concern

  def calculate_path
    updated_path = build_path_from_coordinates
    set_path_attributes(updated_path)
  end

  def calculate_distance
    calculated_distance = calculate_distance_from_coordinates
    self.distance = convert_distance_for_storage(calculated_distance)
  end

  def recalculate_path!
    calculate_path
    save_if_changed!
  end

  def recalculate_distance!
    calculate_distance
    save_if_changed!
  end

  def recalculate_path_and_distance!
    calculate_path
    calculate_distance
    save_if_changed!
  end

  private

  def path_coordinates
    points.pluck(:lonlat)
  end

  def build_path_from_coordinates
    Tracks::BuildPath.new(path_coordinates).call
  end

  def set_path_attributes(updated_path)
    self.path = updated_path if respond_to?(:path=)
    self.original_path = updated_path if respond_to?(:original_path=)
  end

  def user_distance_unit
    user.safe_settings.distance_unit
  end

  def calculate_distance_from_coordinates
    Point.total_distance(points, user_distance_unit)
  end

  def convert_distance_for_storage(calculated_distance)
    if track_model?
      convert_distance_to_meters(calculated_distance)
    else
      # For Trip model - store rounded distance in user's preferred unit
      calculated_distance.round
    end
  end

  def track_model?
    self.class.name == 'Track'
  end

  def convert_distance_to_meters(calculated_distance)
    # For Track model - convert to meters for storage (Track expects distance in meters)
    case user_distance_unit.to_s
    when 'miles', 'mi'
      (calculated_distance * 1609.344).round(2) # miles to meters
    else
      (calculated_distance * 1000).round(2) # km to meters
    end
  end

  def save_if_changed!
    save! if changed?
  end
end

# frozen_string_literal: true

module Calculateable
  extend ActiveSupport::Concern

  def calculate_path
    updated_path = build_path_from_coordinates
    set_path_attributes(updated_path)
  end

  def calculate_distance
    calculated_distance_meters = calculate_distance_from_coordinates

    self.distance = convert_distance_for_storage(calculated_distance_meters)
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
    points.order(:timestamp).pluck(:lonlat)
  end

  def build_path_from_coordinates
    Tracks::BuildPath.new(path_coordinates).call
  end

  def set_path_attributes(updated_path)
    self.path = updated_path if respond_to?(:path=)
    self.original_path = updated_path if respond_to?(:original_path=)
  end

  def calculate_distance_from_coordinates
    # Always calculate in meters for consistent storage
    # Order points by timestamp to ensure correct distance calculation
    Point.total_distance(points.order(:timestamp), :m)
  end

  def convert_distance_for_storage(calculated_distance_meters)
    # Store as integer meters for consistency
    calculated_distance_meters.round
  end

  def track_model?
    self.class.name == 'Track'
  end

  def save_if_changed!
    save! if changed?
  end
end

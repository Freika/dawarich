class RoutePreset < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validate :via_points_must_be_an_array_of_points

  before_validation :normalize_via_points

  private

  def normalize_via_points
    self.via_points = [] if via_points.nil?
  end

  def via_points_must_be_an_array_of_points
    unless via_points.is_a?(Array)
      errors.add(:via_points, "must be an array")
      return
    end

    via_points.each do |point|
      unless point.is_a?(Hash) || point.is_a?(ActionController::Parameters)
        errors.add(:via_points, "must contain point hashes")
        next
      end

      lat = point[:lat] || point["lat"]
      lng = point[:lng] || point["lng"]

      if lat.nil? || lng.nil?
        errors.add(:via_points, "each point must include lat and lng")
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Outlier detection integration', type: :model do
  let(:user) { create(:user) }
  let(:base_time) { DateTime.new(2024, 5, 1, 12, 0, 0).to_i }

  it 'flags outliers and excludes them from distance calculations' do
    # Create a sequence: London -> Tokyo (spike) -> London
    p1 = create(:point, user: user, latitude: 51.5074, longitude: -0.1278,
                lonlat: 'POINT(-0.1278 51.5074)', timestamp: base_time)
    p2 = create(:point, user: user, latitude: 35.6762, longitude: 139.6503,
                lonlat: 'POINT(139.6503 35.6762)', timestamp: base_time + 60)
    p3 = create(:point, user: user, latitude: 51.5080, longitude: -0.1280,
                lonlat: 'POINT(-0.1280 51.5080)', timestamp: base_time + 120)

    # Distance before detection (includes the Tokyo teleport)
    all_points = user.points.order(:timestamp).to_a
    distance_before = Point.calculate_distance_for_array_geocoder(all_points)

    # Run outlier detection
    count = Points::OutlierDetector.new(user).call

    expect(count).to eq(1)
    expect(p2.reload.outlier).to be true

    # Distance after detection (excludes the Tokyo teleport)
    clean_points = user.points.not_outlier.order(:timestamp).to_a
    distance_after = Point.calculate_distance_for_array_geocoder(clean_points)

    # The distance should be dramatically smaller
    expect(distance_after).to be < distance_before
    expect(distance_after).to be < 1 # Less than 1 km (London to London ~67m)
  end
end

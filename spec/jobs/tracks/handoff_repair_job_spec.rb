# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::HandoffRepairJob, type: :job do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }
  let(:started_at) { 3.months.ago.change(hour: 8) }

  def track_with_points(tracker_id, offsets)
    points = offsets.map do |seconds, lon|
      create(:point, user:, tracker_id:, timestamp: started_at.to_i + seconds, lonlat: "POINT(#{lon} -40.0)")
    end
    path = "LINESTRING(#{points.map { |point| "#{point.lon} #{point.lat}" }.join(', ')})"
    track = create(:track, user:, tracker_id:, original_path: path,
                           start_at: Time.zone.at(points.first.timestamp), end_at: Time.zone.at(points.last.timestamp))
    Point.where(id: points.map(&:id)).update_all(track_id: track.id)
  end

  it 'cuts a track that bridges another tracker' do
    track_with_points('owntracks-phone', [[0, -140.002], [60, -140.0], [1200, -139.95], [1260, -139.948]])
    track_with_points('watch-gpx', [[120, -140.0], [660, -139.975], [1140, -139.95]])
    user.tracks.update_all(created_at: 30.days.ago)

    described_class.perform_now(user.id, 12.months.ago.to_i)

    expect(user.tracks.reload.count).to eq(3)
  end
end

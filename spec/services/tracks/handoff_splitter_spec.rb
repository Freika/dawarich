# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::HandoffSplitter do
  let(:user) { create(:user, settings: { 'timezone' => 'UTC' }) }

  def track_with_points(tracker_id, offsets, started_at:)
    points = offsets.map do |seconds, lon|
      create(:point, user:, tracker_id:, timestamp: started_at.to_i + seconds, lonlat: "POINT(#{lon} -40.0)")
    end
    path = "LINESTRING(#{points.map { |point| "#{point.lon} #{point.lat}" }.join(', ')})"
    track = create(:track, user:, tracker_id:, original_path: path,
                           start_at: Time.zone.at(points.first.timestamp), end_at: Time.zone.at(points.last.timestamp))
    Point.where(id: points.map(&:id)).update_all(track_id: track.id)
    [track, points]
  end

  def bridged_day(started_at)
    phone_track, phone_points = track_with_points(
      'owntracks-phone', [[0, -140.002], [60, -140.0], [1200, -139.95], [1260, -139.948]], started_at:
    )
    _watch_track, watch_points = track_with_points(
      'watch-gpx', [[120, -140.0], [660, -139.975], [1140, -139.95]], started_at:
    )
    user.tracks.update_all(created_at: 30.days.ago)
    [phone_track, phone_points, watch_points]
  end

  def track_sections
    user.tracks.reload.order(:start_at, :id).map { |track| track.points.order(:timestamp).pluck(:id) }
  end

  describe '#repair' do
    it 'cuts an older track that bridges another tracker within the window' do
      _phone_track, phone_points, watch_points = bridged_day(3.months.ago.change(hour: 8))

      expect(described_class.new(user).call).to eq(0)
      expect(described_class.new(user).repair(from: 12.months.ago)).to eq(1)

      expect(track_sections).to eq(
        [phone_points.first(2).map(&:id), watch_points.map(&:id), phone_points.last(2).map(&:id)]
      )
    end

    it 'leaves bridging tracks that started before the window' do
      bridged_day(14.months.ago.change(hour: 8))

      expect(described_class.new(user).repair(from: 12.months.ago)).to eq(0)
      expect(user.tracks.count).to eq(2)
    end
  end
end

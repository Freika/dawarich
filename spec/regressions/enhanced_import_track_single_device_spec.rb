# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enhanced import keeps extracted tracks on a single device' do
  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500
           })
  end
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:base_time) { 1.hour.ago.to_i }

  let(:extracted_track) do
    EnhancedImport::Extracted::Track.new(
      tracker_id: "import-#{import.id}-activity-#{base_time}",
      start_at: Time.zone.at(base_time),
      end_at: Time.zone.at(base_time + 900),
      distance_m: 1500,
      transportation_mode: 'driving',
      confidence: 90,
      source_label: 'google_phone_takeout',
      segments: []
    )
  end

  subject(:result) do
    described_track_writer.upsert(extracted_track, skip_segment_detection: true)
  end

  let(:described_track_writer) { EnhancedImport::Writers::TrackWriter.new(user, import) }

  def create_points(tracker_id:, count:, offset:, lon_base:)
    count.times do |i|
      create(
        :point,
        user: user,
        import_id: import.id,
        tracker_id: tracker_id,
        timestamp: base_time + offset + (i * 60),
        lonlat: "POINT(#{lon_base + (i * 0.0001)} #{52.52 + (i * 0.0001)})"
      )
    end
  end

  context 'when the time window holds points from two devices' do
    before do
      create_points(tracker_id: 'phone', count: 8, offset: 0, lon_base: 13.405)
      create_points(tracker_id: 'tablet', count: 3, offset: 30, lon_base: 20.100)
    end

    it 'builds the track from the dominant device only' do
      track, created = result

      expect(created).to be true
      expect(track).to be_present

      tracker_ids = Point.where(track_id: track.id).distinct.pluck(:tracker_id)
      expect(tracker_ids).to eq(['phone'])
    end

    it 'leaves the other device\'s points unassigned' do
      track, = result

      tablet_points = Point.where(user_id: user.id, import_id: import.id, tracker_id: 'tablet')
      expect(tablet_points.pluck(:track_id).uniq).to eq([nil])
      expect(tablet_points.count).to eq(3)
      expect(track.id).to be_present
    end
  end

  context 'when every point in the window is from one device' do
    before do
      create_points(tracker_id: 'phone', count: 10, offset: 0, lon_base: 13.405)
    end

    it 'uses all of them' do
      track, created = result

      expect(created).to be true
      expect(Point.where(track_id: track.id).count).to eq(10)
    end
  end
end

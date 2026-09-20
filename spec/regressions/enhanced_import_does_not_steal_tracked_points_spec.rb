# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Extraction leaves already-tracked points alone' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:base_time) { 2.hours.ago.to_i }
  let(:existing_track) { create(:track, user: user) }

  let(:extracted_track) do
    EnhancedImport::Extracted::Track.new(
      tracker_id: "import-#{import.id}-activity-#{base_time}",
      start_at: Time.zone.at(base_time),
      end_at: Time.zone.at(base_time + 900),
      distance_m: 800,
      transportation_mode: 'driving',
      confidence: 90,
      source_label: 'google_phone_takeout',
      segments: []
    )
  end

  def build_points(count:, track_id:, offset:)
    count.times.map do |i|
      create(:point, user: user, import_id: import.id, tracker_id: 'phone',
                     track_id: track_id, timestamp: base_time + offset + (i * 60),
                     lonlat: "POINT(#{12.3712 + (i * 0.001)} #{51.3402 + (i * 0.001)})")
    end
  end

  it 'does not reassign points owned by another track' do
    claimed = build_points(count: 4, track_id: existing_track.id, offset: 0)
    build_points(count: 4, track_id: nil, offset: 300)

    EnhancedImport::Writers::TrackWriter.new(user, import)
                                        .upsert(extracted_track, skip_segment_detection: true)

    expect(claimed.map { |p| p.reload.track_id }.uniq).to eq([existing_track.id])
    expect(existing_track.reload.points.count).to eq(4)
  end

  it 'builds the extracted track from the unclaimed points only' do
    build_points(count: 4, track_id: existing_track.id, offset: 0)
    free = build_points(count: 4, track_id: nil, offset: 300)

    track, created = EnhancedImport::Writers::TrackWriter.new(user, import)
                                                         .upsert(extracted_track, skip_segment_detection: true)

    expect(created).to be true
    expect(Point.where(track_id: track.id).pluck(:id)).to match_array(free.map(&:id))
  end
end

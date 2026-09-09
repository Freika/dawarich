# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Re-extraction finds the track it created before' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:activity_start) { Time.zone.parse('2026-02-10 08:00:00') }

  # The activity boundary deliberately precedes the first point, which is what
  # the stored start_at ends up being.
  let(:extracted_track) do
    EnhancedImport::Extracted::Track.new(
      tracker_id: "import-#{import.id}-activity-#{activity_start.to_i}",
      start_at: activity_start,
      end_at: activity_start + 1.hour,
      distance_m: 900,
      transportation_mode: 'driving',
      confidence: 90,
      source_label: 'google_phone_takeout',
      segments: [
        EnhancedImport::Extracted::TrackSegment.new(
          start_index: 0, end_index: 0, transportation_mode: 'driving',
          confidence: 90, source_label: 'google_phone_takeout'
        )
      ]
    )
  end

  before do
    5.times do |i|
      create(:point, user: user, import_id: import.id, tracker_id: 'phone',
                     timestamp: (activity_start + 5.minutes).to_i + (i * 60),
                     lonlat: "POINT(#{12.3712 + (i * 0.001)} #{51.3402 + (i * 0.001)})")
    end
  end

  it 'reuses the same track instead of reporting nothing on a second run' do
    writer = EnhancedImport::Writers::TrackWriter.new(user, import)

    first, created = writer.upsert(extracted_track, skip_segment_detection: true)
    expect(created).to be true
    expect(first.start_at).not_to eq(activity_start)

    second, created_again = writer.upsert(extracted_track, skip_segment_detection: true)

    expect(created_again).to be false
    expect(second.id).to eq(first.id)
    expect(Track.where(user_id: user.id).count).to eq(1)
  end

  it 'rebuilds segments when the trust choice flips' do
    writer = EnhancedImport::Writers::TrackWriter.new(user, import)
    track, = writer.upsert(extracted_track, skip_segment_detection: true)
    EnhancedImport::Writers::SegmentWriter.new.upsert(track, extracted_track.segments.first)

    expect(track.reload.track_segments.count).to eq(1)

    writer.upsert(extracted_track, skip_segment_detection: true)

    expect(track.reload.track_segments.count).to eq(0)
  end
end

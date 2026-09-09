# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Backfilling an old import classifies the tracks it already has' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:activity_start) { Time.zone.parse('2026-01-20 07:00:00') }
  let(:generated_track) { create(:track, user: user, dominant_mode: nil) }

  let(:extracted_track) do
    EnhancedImport::Extracted::Track.new(
      tracker_id: "import-#{import.id}-activity-#{activity_start.to_i}",
      start_at: activity_start,
      end_at: activity_start + 1.hour,
      distance_m: 1200,
      transportation_mode: 'cycling',
      confidence: 95,
      source_label: 'google_phone_takeout',
      segments: [
        EnhancedImport::Extracted::TrackSegment.new(
          start_index: 0, end_index: 0, transportation_mode: 'cycling',
          confidence: 95, source_label: 'google_phone_takeout'
        )
      ]
    )
  end

  before do
    5.times do |i|
      create(:point, user: user, import_id: import.id, track_id: generated_track.id,
                     timestamp: (activity_start + 5.minutes).to_i + (i * 60),
                     lonlat: "POINT(#{12.3712 + (i * 0.001)} #{51.3402 + (i * 0.001)})")
    end
  end

  it 'reuses the generated track rather than reporting nothing' do
    track, created = EnhancedImport::Writers::TrackWriter.new(user, import)
                                                         .upsert(extracted_track, skip_segment_detection: true)

    expect(track).to be_present
    expect(created).to be false
    expect(track.id).to eq(generated_track.id)
  end

  it 'does not steal the points or create a duplicate track' do
    expect do
      EnhancedImport::Writers::TrackWriter.new(user, import)
                                          .upsert(extracted_track, skip_segment_detection: true)
    end.not_to(change(Track, :count))

    expect(Point.where(track_id: generated_track.id).count).to eq(5)
  end

  it 'lets the source classification land on that track' do
    track, = EnhancedImport::Writers::TrackWriter.new(user, import)
                                                 .upsert(extracted_track, skip_segment_detection: true)
    EnhancedImport::Writers::SegmentWriter.new.upsert(track, extracted_track.segments.first)
    track.update_dominant_mode!

    expect(track.reload.track_segments.pluck(:transportation_mode)).to eq(['cycling'])
    expect(track.dominant_mode).to eq('cycling')
  end
end

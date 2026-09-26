# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Undoing an extraction reclassifies the generated tracks it classified' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:activity_start) { Time.zone.parse('2026-03-02 08:00:00') }
  let(:adopted_track) { create(:track, user: user, tracker_id: 'phone', dominant_mode: :walking) }
  let(:untouched_track) { create(:track, user: user, tracker_id: 'watch', dominant_mode: :walking) }
  let!(:points) do
    Array.new(10) do |i|
      create(:point, user: user, import_id: import.id, tracker_id: 'phone', track_id: adopted_track.id,
                     timestamp: (activity_start + 5.minutes).to_i + (i * 60),
                     lonlat: "POINT(#{12.3712 + (i * 0.001)} #{51.3402 + (i * 0.001)})")
    end
  end
  let(:activity) do
    EnhancedImport::Extracted::Track.new(
      tracker_id: "import-#{import.id}-activity-#{points.first.timestamp}",
      start_at: Time.zone.at(points.first.timestamp) - 30.seconds,
      end_at: Time.zone.at(points[6].timestamp) + 30.seconds,
      transportation_mode: 'cycling',
      source_label: 'google_phone_takeout',
      segments: [
        EnhancedImport::Extracted::TrackSegment.new(
          start_index: 0, end_index: 0, transportation_mode: 'cycling', source_label: 'google_phone_takeout'
        )
      ]
    )
  end

  before do
    create(:point, user: user, import_id: import.id, tracker_id: 'watch', track_id: untouched_track.id,
                   timestamp: activity_start.to_i - 3600, lonlat: 'POINT(13.4 52.5)')
    create(:track_segment, track: untouched_track, start_index: 0, end_index: 0, source: 'inferred')
    create(:track_segment, track: adopted_track, start_index: nil, end_index: nil, transportation_mode: :bus,
                           start_at: Time.zone.at(points[8].timestamp), end_at: Time.zone.at(points[9].timestamp),
                           source: 'user', corrected_at: 1.day.ago)
    allow_any_instance_of(EnhancedImport::Translator).to receive(:translate) { |_translator, &block| block.call(activity) }
    EnhancedImport::ExtractJob.new.perform(import.id)
  end

  it 'enqueues reclassification for the generated tracks that carry its source segments' do
    expect(adopted_track.track_segments.where(source: 'google_phone_takeout')).to exist

    EnhancedImport::Destroy.new(import.reload).call

    expect(TransportationModes::ReclassifyTrackJob).to have_been_enqueued.with(adopted_track.id)
    expect(TransportationModes::ReclassifyTrackJob).not_to have_been_enqueued.with(untouched_track.id)
  end

  it 'leaves those tracks classified by inference with the manual correction intact' do
    EnhancedImport::Destroy.new(import.reload).call
    perform_enqueued_jobs(only: TransportationModes::ReclassifyTrackJob)

    segments = adopted_track.track_segments.reload
    expect(segments.where(source: 'google_phone_takeout')).not_to exist
    expect(segments.auto_classified).to exist
    expect(segments.manually_corrected.pluck(:transportation_mode)).to eq(['bus'])
  end
end

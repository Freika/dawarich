# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Re-extracting without trusting the source clears its modes from adopted tracks' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:activity_start) { Time.zone.parse('2026-03-02 08:00:00') }
  let(:adopted_track) { create(:track, user: user, tracker_id: 'phone', dominant_mode: :walking) }
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
  let!(:correction) do
    create(:track_segment, track: adopted_track, start_index: nil, end_index: nil, transportation_mode: :bus,
                           start_at: Time.zone.at(points[8].timestamp), end_at: Time.zone.at(points[9].timestamp),
                           source: 'user', corrected_at: 1.day.ago)
  end

  def extract(trust_source:)
    import.update_columns(additional_data_extraction: { 'options' => { 'trust_source' => trust_source } })
    EnhancedImport::ExtractJob.new.perform(import.id)
    perform_enqueued_jobs(only: TransportationModes::ReclassifyTrackJob)
  end

  def segment_rows
    adopted_track.track_segments.reload.order(:start_at).pluck(:source, :transportation_mode, :start_at, :end_at)
  end

  before do
    allow_any_instance_of(EnhancedImport::Translator).to receive(:translate) { |_translator, &block| block.call(activity) }
  end

  it 'replaces them with inference, keeps the correction, and a later recalculation changes nothing' do
    extract(trust_source: true)
    expect(adopted_track.track_segments.where(source: 'google_phone_takeout')).to exist

    extract(trust_source: false)

    segments = adopted_track.track_segments.reload
    expect(segments.where(source: 'google_phone_takeout')).not_to exist
    expect(segments.auto_classified).to exist
    expect(TrackSegment.find(correction.id).transportation_mode).to eq('bus')

    before_recalculation = segment_rows
    TransportationModes::UserReclassifyJob.perform_now(user.id)
    perform_enqueued_jobs(only: TransportationModes::ReclassifyTrackJob)
    expect(segment_rows).to eq(before_recalculation)
  end

  it 'rebuilds the tracks the extraction wrote itself without queuing a second reclassification' do
    Point.where(id: points.map(&:id)).update_all(track_id: nil)
    extract(trust_source: true)
    own_track = Track.find_by!(import_id: import.id)
    clear_enqueued_jobs

    import.update_columns(additional_data_extraction: { 'options' => { 'trust_source' => false } })
    EnhancedImport::ExtractJob.new.perform(import.id)

    expect(own_track.track_segments.reload.where(source: 'google_phone_takeout')).not_to exist
    expect(TransportationModes::ReclassifyTrackJob).not_to have_been_enqueued.with(own_track.id)
  end

  it 'leaves the source modes in place when the re-extraction still trusts the source' do
    extract(trust_source: true)

    extract(trust_source: true)

    expect(adopted_track.track_segments.where(source: 'google_phone_takeout')).to exist
  end
end

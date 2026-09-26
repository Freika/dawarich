# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Source segments replace inferred ones but never a manual correction' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:activity_start) { Time.zone.parse('2026-03-02 08:00:00') }
  let(:generated_track) { create(:track, user: user, tracker_id: 'phone', dominant_mode: :walking) }
  let!(:points) do
    Array.new(10) do |i|
      create(:point, user: user, import_id: import.id, tracker_id: 'phone', track_id: generated_track.id,
                     timestamp: (activity_start + 5.minutes).to_i + (i * 60),
                     lonlat: "POINT(#{12.3712 + (i * 0.001)} #{51.3402 + (i * 0.001)})")
    end
  end

  def at(index)
    Time.zone.at(points[index].timestamp)
  end

  def segment(track, first, last, mode, **attrs)
    create(:track_segment, track: track, transportation_mode: mode, start_index: nil, end_index: nil,
                           start_at: at(first), end_at: at(last), source: 'inferred', **attrs)
  end

  def activity(mode, first, last)
    EnhancedImport::Extracted::Track.new(
      tracker_id: "import-#{import.id}-activity-#{at(first).to_i}",
      start_at: at(first) - 30.seconds,
      end_at: at(last) + 30.seconds,
      transportation_mode: mode,
      confidence: 90,
      source_label: 'google_phone_takeout',
      segments: [
        EnhancedImport::Extracted::TrackSegment.new(
          start_index: 0, end_index: 0, transportation_mode: mode,
          confidence: 90, source_label: 'google_phone_takeout'
        )
      ]
    )
  end

  def extract(*items)
    allow_any_instance_of(EnhancedImport::Translator).to receive(:translate) { |_translator, &block| items.each(&block) }
    EnhancedImport::ExtractJob.new.perform(import.id)
  end

  def segments_of(track)
    track.track_segments.reload.order(Arel.sql('COALESCE(start_index, 0)'), :start_at)
         .map { |s| [s.transportation_mode, s.source, s.start_index, s.end_index] }
  end

  it 'replaces the inferred segments of a generated track with the source classification' do
    segment(generated_track, 0, 4, :walking)
    segment(generated_track, 5, 9, :driving)

    extract(activity('cycling', 0, 9))

    expect(segments_of(generated_track)).to eq([['cycling', 'google_phone_takeout', 0, 9]])
    expect(generated_track.reload.dominant_mode).to eq('cycling')
    expect(import.reload.extraction_counts[:tracks]).to eq(1)
  end

  it 'keeps a segment the user corrected by hand and fills the rest from the source' do
    segment(generated_track, 0, 3, :walking)
    corrected = segment(generated_track, 4, 6, :bus, source: 'user', corrected_at: 1.day.ago)
    segment(generated_track, 7, 9, :walking)

    extract(activity('driving', 0, 9))

    expect(corrected.reload).to have_attributes(transportation_mode: 'bus', corrected_at: be_present)
    expect(segments_of(generated_track) - [['bus', 'user', nil, nil]]).to eq(
      [['driving', 'google_phone_takeout', 0, 3], ['driving', 'google_phone_takeout', 7, 9]]
    )
  end

  it 'gives each activity its own stretch of a shared generated track' do
    segment(generated_track, 0, 9, :driving)

    extract(activity('walking', 0, 4), activity('driving', 5, 9))

    expect(segments_of(generated_track)).to eq(
      [['walking', 'google_phone_takeout', 0, 4], ['driving', 'google_phone_takeout', 5, 9]]
    )
  end

  it "keeps a correction on the import's own track when it is extracted again" do
    source_track = create(:track, user: user, import_id: import.id,
                                  tracker_id: "import-#{import.id}-activity-#{at(0).to_i}",
                                  start_at: at(0), end_at: at(9))
    Point.where(id: points.map(&:id)).update_all(track_id: source_track.id)
    corrected = create(:track_segment, track: source_track, transportation_mode: :bus, start_index: 0, end_index: 9,
                                       source: 'user', corrected_at: 1.day.ago)

    extract(activity('driving', 0, 9))

    expect(TrackSegment.exists?(corrected.id)).to be(true)
    expect(corrected.reload.transportation_mode).to eq('bus')
  end
end

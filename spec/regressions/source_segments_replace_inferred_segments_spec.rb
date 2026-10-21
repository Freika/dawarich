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

  def index_at(time)
    points.index { |point| point.timestamp == time.to_i }
  end

  def segment_row(segment)
    bounds = [segment.start_index, segment.end_index]
    bounds = [index_at(segment.start_at), index_at(segment.end_at)] if segment.start_at
    [segment.transportation_mode, segment.source, *bounds]
  end

  def segments_of(track)
    track.track_segments.reload.map { |segment| segment_row(segment) }.sort_by { |row| row[2] }
  end

  def legacy_segment(first, last, mode)
    create(:track_segment, track: generated_track, transportation_mode: mode, start_index: first, end_index: last,
                           start_at: at(first), end_at: at(last), source: 'inferred')
  end

  it 'replaces the inferred segments of a generated track with the source classification' do
    segment(generated_track, 0, 4, :walking)
    segment(generated_track, 5, 9, :driving)

    extract(activity('cycling', 0, 9))

    expect(segments_of(generated_track)).to eq([['cycling', 'google_phone_takeout', 0, 9]])
    expect(generated_track.track_segments.sole)
      .to have_attributes(start_index: nil, end_index: nil, distance: be_positive, duration: 540)
    expect(generated_track.reload.dominant_mode).to eq('cycling')
    expect(import.reload.extraction_counts[:tracks]).to eq(1)
  end

  it 'keeps a segment the user corrected by hand and fills the rest from the source' do
    segment(generated_track, 0, 3, :walking)
    corrected = segment(generated_track, 4, 6, :bus, source: 'user', corrected_at: 1.day.ago)
    segment(generated_track, 7, 9, :walking)

    extract(activity('driving', 0, 9))

    expect(corrected.reload).to have_attributes(transportation_mode: 'bus', corrected_at: be_present)
    expect(segments_of(generated_track)).to eq(
      [['driving', 'google_phone_takeout', 0, 3], ['bus', 'user', 4, 6], ['driving', 'google_phone_takeout', 7, 9]]
    )
  end

  it 'gives each activity its own stretch of a shared generated track' do
    segment(generated_track, 0, 9, :driving)

    extract(activity('walking', 0, 4), activity('driving', 5, 9))

    expect(segments_of(generated_track)).to eq(
      [['walking', 'google_phone_takeout', 0, 4], ['driving', 'google_phone_takeout', 5, 9]]
    )
  end

  def inferred_spans(track)
    track.track_segments.reload.where(source: 'inferred').order(:start_at)
         .map { |s| [s.transportation_mode, s.start_at.to_i, s.end_at.to_i, s.duration] }
  end

  def span(mode, first, last)
    [mode, points[first].timestamp, points[last].timestamp, points[last].timestamp - points[first].timestamp]
  end

  it 'trims inferred segments that cross the window edges to the part outside the window' do
    segment(generated_track, 0, 4, :walking)
    segment(generated_track, 5, 9, :driving)

    extract(activity('cycling', 2, 7))

    expect(inferred_spans(generated_track)).to eq([span('walking', 0, 1), span('driving', 8, 9)])
    expect(segments_of(generated_track)).to include(['cycling', 'google_phone_takeout', 2, 7])
  end

  it 'splits an inferred segment that spans the whole window into the parts on either side' do
    segment(generated_track, 0, 9, :walking)

    extract(activity('cycling', 3, 6))

    expect(inferred_spans(generated_track)).to eq([span('walking', 0, 2), span('walking', 7, 9)])
  end

  it "leaves another import's source segments in place" do
    segment(generated_track, 0, 4, :walking, source: 'google_semantic_history')
    segment(generated_track, 5, 9, :walking)

    extract(activity('driving', 0, 9))

    expect(segments_of(generated_track)).to eq(
      [['walking', 'google_semantic_history', 0, 4], ['driving', 'google_phone_takeout', 5, 9]]
    )
  end

  it 'splits an older segment that carries both point indexes and times' do
    legacy_segment(0, 9, :walking)

    extract(activity('cycling', 3, 6))

    expect(segments_of(generated_track)).to eq(
      [['walking', 'inferred', 0, 2], ['cycling', 'google_phone_takeout', 3, 6], ['walking', 'inferred', 7, 9]]
    )
    expect(generated_track.track_segments.where(source: 'inferred').pluck(:start_index, :end_index))
      .to all(eq([nil, nil]))
  end

  it 'writes the source over an older segment that starts at the same point' do
    legacy_segment(0, 4, :walking)
    legacy_segment(5, 9, :driving)

    extract(activity('cycling', 0, 6))

    expect(segments_of(generated_track)).to eq(
      [['cycling', 'google_phone_takeout', 0, 6], ['driving', 'inferred', 7, 9]]
    )
    expect(import.reload.extraction_counts[:segments]).to eq(1)
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

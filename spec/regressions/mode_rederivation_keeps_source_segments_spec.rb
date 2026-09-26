# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Re-deriving transportation modes keeps source segments and manual corrections' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:start_time) { Time.zone.parse('2026-01-05 09:00 UTC') }

  def build_track(from: start_time, seed: 11)
    trip = TransportationTraceGenerator.trip(legs: [{ mode: :walking, duration_s: 900, dt_s: 10 }],
                                             start_time: from, seed: seed)
    points = trip[:points]
    track = create(:track, user: user, tracker_id: 'phone', dominant_mode: :unknown,
                           start_at: Time.zone.at(points.first[:timestamp]),
                           end_at: Time.zone.at(points.last[:timestamp]))
    now = Time.current
    Point.insert_all(points.map do |p|
      { user_id: user.id, track_id: track.id, import_id: import.id, tracker_id: 'phone',
        timestamp: p[:timestamp], lonlat: "SRID=4326;POINT(#{p[:lon]} #{p[:lat]})",
        accuracy: p[:accuracy], velocity: p[:velocity].to_s, created_at: now, updated_at: now }
    end)
    track
  end

  def segment(track, from, to, **attrs)
    create(:track_segment, :anchored, track: track, start_at: track.start_at + from, end_at: track.start_at + to,
                                      **attrs)
  end

  def source_segment(track)
    segment(track, 100, 300, transportation_mode: :train, source: 'google_phone_takeout', confidence: :high)
  end

  def corrected_segment(track)
    segment(track, 400, 600, transportation_mode: :bus, source: 'user', corrected_at: 1.day.ago)
  end

  def inferred_segment(track)
    segment(track, 700, 800, transportation_mode: :flying, source: 'inferred')
  end

  def expect_only_inference_replaced(track, kept:, replaced:)
    segments = track.track_segments.reload.to_a
    expect(segments.map(&:id)).to include(*kept.map(&:id))
    expect(segments.map(&:id)).not_to include(*replaced.map(&:id))
    kept.each do |original|
      expect(segments.find { |s| s.id == original.id }.transportation_mode).to eq(original.transportation_mode)
      overlapping = (segments - kept).select { |s| s.start_at < original.end_at && s.end_at > original.start_at }
      expect(overlapping).to be_empty
    end
  end

  shared_examples 'a path that replaces only inference' do
    it 'keeps the source segment and the correction and replaces the inferred one' do
      track = build_track
      kept = [source_segment(track), corrected_segment(track)]
      inferred = inferred_segment(track)

      rederive.call(track)

      expect_only_inference_replaced(track, kept: kept, replaced: [inferred])
    end
  end

  describe 'the Recalculate button' do
    let(:rederive) do
      lambda do |_track|
        TransportationModes::UserReclassifyJob.perform_now(user.id)
        perform_enqueued_jobs(only: TransportationModes::ReclassifyTrackJob)
      end
    end

    it_behaves_like 'a path that replaces only inference'
  end

  describe 'a change of the enabled modes in settings' do
    let(:rederive) do
      lambda do |_track|
        Users::SettingsUpdater.new(user, { 'enabled_transportation_modes' => %w[walking cycling train bus] }).call
        perform_enqueued_jobs(only: TransportationModes::UserReclassifyJob)
        perform_enqueued_jobs(only: TransportationModes::ReclassifyTrackJob)
      end
    end

    it_behaves_like 'a path that replaces only inference'
  end

  describe 'the fleet reclassification' do
    let(:rederive) do
      lambda do |_track|
        TransportationModes::FleetReclassifyJob.perform_now
        perform_enqueued_jobs(only: TransportationModes::ReclassifyTrackJob)
      end
    end

    it_behaves_like 'a path that replaces only inference'
  end

  describe 'the transportation modes backfill' do
    let(:rederive) do
      lambda do |_track|
        DataMigrations::BackfillTransportationModesJob.perform_now
        perform_enqueued_jobs(only: TransportationModes::ReclassifyTrackJob)
      end
    end

    it_behaves_like 'a path that replaces only inference'
  end

  describe 'an activity backfill of the import' do
    let(:rederive) { ->(_track) { TransportationModes::ImportBackfillJob.perform_now(import.id) } }

    it_behaves_like 'a path that replaces only inference'
  end

  describe 'a metadata refresh after chunks moved the track bounds' do
    let(:rederive) do
      lambda do |track|
        track.update_columns(start_at: track.start_at - 120)
        expect(Tracks::MetadataRefresher.new(user).call[:refreshed]).to eq(1)
      end
    end

    it_behaves_like 'a path that replaces only inference'
  end

  describe 'a single orphan point attached to the track' do
    let(:rederive) do
      lambda do |track|
        last = track.points.order(:timestamp).last
        orphan = create(:point, user: user, tracker_id: 'phone', timestamp: last.timestamp + 20,
                                lonlat: last.lonlat.to_s)
        expect(Tracks::OrphanPointAttacher.new(user, orphan, [last, orphan]).call).to eq(track)
      end
    end

    it_behaves_like 'a path that replaces only inference'
  end

  describe 'a realtime merge of two consecutive tracks' do
    it 'keeps the source segment and the correction of both tracks' do
      older = build_track
      newer = build_track(from: older.end_at + 30, seed: 12)
      kept = [corrected_segment(older), source_segment(newer)]
      replaced = [inferred_segment(older), inferred_segment(newer)]

      expect(Tracks::Merger.new(older, newer).call).to be(true)

      expect_only_inference_replaced(older, kept: kept, replaced: replaced)
    end
  end

  describe 'resetting a corrected segment to automatic' do
    it 'keeps the source segment' do
      track = build_track
      kept = source_segment(track)
      corrected = corrected_segment(track)

      expect(Tracks::SegmentEditor.new(corrected, user).reset_to_auto.success?).to be(true)

      expect_only_inference_replaced(track, kept: [kept], replaced: [corrected])
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Generation never builds a track across or inside a kept track of the same device' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :owntracks, name: 'phone.rec') }
  let(:base) { 3.days.ago.beginning_of_hour.to_i }

  def points_at(offsets, import_id: nil, tracker_id: 'phone')
    offsets.map do |offset|
      create(:point, user: user, import_id: import_id, tracker_id: tracker_id, timestamp: base + offset,
                     lonlat: "POINT(#{13.4 + (offset * 0.00001)} 52.5)")
    end
  end

  def corrected_track(offsets, tracker_id: 'phone')
    points = points_at(offsets, tracker_id: tracker_id)
    track = create(:track, user: user, tracker_id: tracker_id, created_at: 3.hours.ago,
                           start_at: Time.zone.at(points.first.timestamp), end_at: Time.zone.at(points.last.timestamp))
    Point.where(id: points.map(&:id)).update_all(track_id: track.id)
    create(:track_segment, :anchored, track: track, start_at: track.start_at, end_at: track.end_at,
                                      transportation_mode: :cycling, source: 'user', corrected_at: 1.day.ago)
    track
  end

  def overlapping(kept)
    user.tracks.where.not(id: kept.id).where('start_at < ? AND end_at > ?', kept.end_at, kept.start_at)
  end

  def track_ids(points)
    Point.where(id: points.map(&:id)).pluck(:track_id)
  end

  def run_leftover_generation
    import.schedule_untracked_track_generation
    perform_enqueued_jobs(only: Tracks::ParallelGeneratorJob)
    perform_enqueued_jobs(only: Tracks::TimeChunkProcessorJob)
  end

  def run_recalculation
    Tracks::ParallelGenerator.new(user, start_at: Time.zone.at(base - 3600), end_at: Time.zone.at(base + 3600),
                                        mode: :bulk).call
    perform_enqueued_jobs(only: Tracks::TimeChunkProcessorJob)
  end

  it 'splits leftover orphans around a short kept track instead of bridging it' do
    before = points_at([0, 60, 120, 180], import_id: import.id)
    kept = corrected_track([240, 300, 360])
    after = points_at([420, 480, 540, 600], import_id: import.id)

    run_leftover_generation

    expect(overlapping(kept)).to be_empty
    expect(user.tracks.where.not(id: kept.id).count).to eq(2)
    expect(track_ids(before + after)).to all(be_present)
  end

  it 'still joins leftover orphans across a kept track of another device' do
    orphans = points_at([0, 60, 120, 180, 420, 480, 540, 600], import_id: import.id)
    corrected_track([240, 300, 360], tracker_id: 'watch')

    run_leftover_generation

    expect(track_ids(orphans).uniq.size).to eq(1)
    expect(track_ids(orphans)).to all(be_present)
  end

  shared_examples 'orphans interleaved with a kept track' do
    it 'builds no track inside the kept one and still tracks the orphans after it' do
      kept = corrected_track([0, 120, 240, 360, 480, 600])
      inside = points_at([60, 90, 300, 330], import_id: import.id)
      after = points_at([720, 780, 840, 900], import_id: import.id)

      generate

      expect(overlapping(kept)).to be_empty
      expect(track_ids(inside)).to all(be_nil)
      expect(track_ids(after)).to all(be_present)
    end
  end

  describe 'leftover generation' do
    def generate = run_leftover_generation

    it_behaves_like 'orphans interleaved with a kept track'
  end

  describe 'a recalculation' do
    def generate = run_recalculation

    it_behaves_like 'orphans interleaved with a kept track'
  end
end

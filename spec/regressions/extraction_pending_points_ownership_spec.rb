# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Points waiting for source extraction belong to their own import' do
  let(:user) { create(:user) }
  let(:base) { 3.days.ago.beginning_of_hour.to_i }
  let(:pending_import) { create(:import, user: user, source: :google_phone_takeout, name: 'records.json') }
  let(:sibling_import) { create(:import, user: user, source: :google_phone_takeout, name: 'timeline.json') }

  def mark_extraction(import, status, started_at: Time.current)
    import.update_columns(
      additional_data_extraction_status: Import.additional_data_extraction_statuses[status],
      additional_data_extraction: { 'started_at' => started_at.iso8601 }
    )
  end

  def create_points(import:, tracker_id:, offset:, count: 6, start: base)
    Array.new(count) do |i|
      create(:point, user: user, import_id: import&.id, tracker_id: tracker_id,
                     timestamp: start + offset + (i * 60),
                     lonlat: "POINT(#{13.4 + (offset / 1000.0) + (i * 0.0005)} 52.5)")
    end
  end

  def run_generation
    perform_enqueued_jobs(only: Tracks::ParallelGeneratorJob)
    perform_enqueued_jobs(only: Tracks::TimeChunkProcessorJob)
  end

  def track_ids(points)
    Point.where(id: points.map(&:id)).pluck(:track_id)
  end

  describe 'generation started by an import' do
    it "takes only that import's points while a sibling waits for extraction" do
      pending_points = create_points(import: pending_import, tracker_id: 'phone', offset: 0)
      sibling_points = create_points(import: sibling_import, tracker_id: 'watch', offset: 30)
      mark_extraction(pending_import, :pending)
      mark_extraction(sibling_import, :completed)

      sibling_import.schedule_untracked_track_generation
      run_generation

      expect(track_ids(pending_points)).to all(be_nil)
      expect(track_ids(sibling_points)).to all(be_present)
    end

    it 'still takes its own points when its extraction is stuck in flight' do
      own_points = create_points(import: pending_import, tracker_id: 'phone', offset: 0)
      sibling_points = create_points(import: sibling_import, tracker_id: 'watch', offset: 30)
      mark_extraction(pending_import, :pending, started_at: 7.hours.ago)
      mark_extraction(sibling_import, :running)

      pending_import.schedule_untracked_track_generation
      run_generation

      expect(track_ids(own_points)).to all(be_present)
      expect(track_ids(sibling_points)).to all(be_nil)
    end
  end

  describe 'the daily generator' do
    let!(:live_points) { create_points(import: nil, tracker_id: 'phone', offset: 0) }
    let!(:pending_points) { create_points(import: pending_import, tracker_id: 'takeout', offset: 30) }

    before do
      user.update!(points_count: user.points.count)
      mark_extraction(pending_import, :pending)
    end

    it 'skips points whose import is still waiting for extraction' do
      Tracks::DailyGenerationJob.perform_now
      run_generation

      expect(track_ids(pending_points)).to all(be_nil)
      expect(track_ids(live_points)).to all(be_present)
    end

    it 'keeps a source track the extraction wrote after the run picked its window' do
      Tracks::DailyGenerationJob.perform_now

      mark_extraction(pending_import, :running)
      source_track = create(:track, user: user, import_id: pending_import.id, tracker_id: 'takeout-activity',
                                    start_at: Time.zone.at(pending_points.first.timestamp),
                                    end_at: Time.zone.at(pending_points.last.timestamp))
      Point.where(id: pending_points.map(&:id)).update_all(track_id: source_track.id)

      run_generation

      expect(Track.exists?(source_track.id)).to be(true)
      expect(track_ids(pending_points)).to all(eq(source_track.id))
    end
  end

  describe 'an extraction that starts while a chunk is running' do
    it 'keeps the chunk from claiming points it loaded before the extraction was queued' do
      live_points = create_points(import: nil, tracker_id: 'phone', offset: 0)
      pending_points = create_points(import: pending_import, tracker_id: 'takeout', offset: 30)
      mark_extraction(pending_import, :not_attempted)
      user.update!(points_count: user.points.count)
      allow_any_instance_of(Tracks::TimeChunkProcessorJob).to receive(:segment_chunk_points)
        .and_wrap_original do |original, points|
          points.load
          mark_extraction(pending_import, :pending)
          original.call(points)
        end

      Tracks::DailyGenerationJob.perform_now
      run_generation

      expect(track_ids(pending_points)).to all(be_nil)
      expect(track_ids(live_points)).to all(be_present)
    end
  end

  describe 'the Cloud large-history backfill' do
    it 'leaves a pending range untouched when a slice reaches it' do
      live_points = create_points(import: nil, tracker_id: 'phone', offset: 0)
      pending_points = create_points(import: pending_import, tracker_id: 'takeout', offset: 30)
      mark_extraction(pending_import, :running)

      Tracks::ThrottledBackfillJob.new.perform(user.id, nil)
      perform_enqueued_jobs(only: Tracks::TimeChunkProcessorJob)

      expect(track_ids(pending_points)).to all(be_nil)
      expect(track_ids(live_points)).to all(be_present)
    end
  end

  describe 'an import that is still being imported' do
    let(:owntracks_import) { create(:import, user: user, source: :owntracks, name: 'phone.rec') }

    before do
      pending_import.update_columns(status: Import.statuses[:processing])
      owntracks_import.update_columns(status: Import.statuses[:processing])
    end

    it 'is skipped by the daily generator when its source will be extracted' do
      processing_points = create_points(import: pending_import, tracker_id: 'takeout', offset: 0)
      owntracks_points = create_points(import: owntracks_import, tracker_id: 'phone', offset: 30)
      user.update!(points_count: user.points.count)

      Tracks::DailyGenerationJob.perform_now
      run_generation

      expect(track_ids(processing_points)).to all(be_nil)
      expect(track_ids(owntracks_points)).to all(be_present)
    end

    it 'is skipped by a backfill slice when its source will be extracted' do
      processing_points = create_points(import: pending_import, tracker_id: 'takeout', offset: 0)
      owntracks_points = create_points(import: owntracks_import, tracker_id: 'phone', offset: 30)

      Tracks::ThrottledBackfillJob.new.perform(user.id, nil)
      perform_enqueued_jobs(only: Tracks::TimeChunkProcessorJob)

      expect(track_ids(processing_points)).to all(be_nil)
      expect(track_ids(owntracks_points)).to all(be_present)
    end
  end

  describe 'orphan reabsorption after a generation run' do
    it 'does not pull pending points into a recent track' do
      recent_start = 2.hours.ago.to_i
      live_points = create_points(import: nil, tracker_id: 'phone', offset: 0, start: recent_start, count: 10)
      recent_track = create(:track, user: user, tracker_id: 'phone',
                                    start_at: Time.zone.at(live_points.first.timestamp),
                                    end_at: Time.zone.at(live_points.last.timestamp))
      Point.where(id: live_points.map(&:id)).update_all(track_id: recent_track.id)
      pending_points = create_points(import: pending_import, tracker_id: 'phone', offset: 90,
                                     start: recent_start, count: 3)
      Point.where(id: pending_points.map(&:id)).update_all(created_at: 10.minutes.ago)
      mark_extraction(pending_import, :pending)

      Tracks::BoundaryDetector.new(user).reabsorb_orphan_points

      expect(track_ids(pending_points)).to all(be_nil)
    end
  end

  describe 'an extraction that starts between choosing and claiming a point' do
    it 'keeps a chunk from attaching a single orphan it chose before the extraction was queued' do
      mark_extraction(sibling_import, :completed)
      kept_points = create_points(import: sibling_import, tracker_id: 'phone', offset: 0, count: 4)
      kept_track = create(:track, user: user, import_id: sibling_import.id, tracker_id: 'phone',
                                  start_at: Time.zone.at(kept_points.first.timestamp),
                                  end_at: Time.zone.at(kept_points.last.timestamp))
      Point.where(id: kept_points.map(&:id)).update_all(track_id: kept_track.id)
      orphan = create_points(import: pending_import, tracker_id: 'phone', offset: 240, count: 1).first
      mark_extraction(pending_import, :not_attempted)
      allow(Tracks::OrphanPointAttacher).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        mark_extraction(pending_import, :pending)
        original.call(*args, **kwargs)
      end

      Tracks::ParallelGenerator.new(user, start_at: Time.zone.at(base - 3600), end_at: Time.zone.at(base + 3600),
                                          mode: :bulk).call
      perform_enqueued_jobs(only: Tracks::TimeChunkProcessorJob)

      expect(Tracks::OrphanPointAttacher).to have_received(:new)
      expect(orphan.reload.track_id).to be_nil
    end

    context 'when reabsorbing orphans into a recent track' do
      let(:recent_start) { 2.hours.ago.to_i }
      let(:recent_track) do
        live_points = create_points(import: nil, tracker_id: 'phone', offset: 0, start: recent_start, count: 10)
        track = create(:track, user: user, tracker_id: 'phone',
                               start_at: Time.zone.at(live_points.first.timestamp),
                               end_at: Time.zone.at(live_points.last.timestamp))
        Point.where(id: live_points.map(&:id)).update_all(track_id: track.id)
        track
      end
      let!(:orphans) do
        points = create_points(import: pending_import, tracker_id: 'phone', offset: 90, start: recent_start, count: 3)
        Point.where(id: points.map(&:id)).update_all(created_at: 10.minutes.ago)
        points
      end

      def between_choosing_and_claiming(&block)
        allow_any_instance_of(Tracks::OrphanReabsorber).to receive(:orphan_point_ids_for)
          .and_wrap_original do |original, track|
            original.call(track).tap { block.call }
          end
      end

      before do
        recent_track
        mark_extraction(pending_import, :not_attempted)
      end

      it 'does not claim orphans whose import became held in between' do
        between_choosing_and_claiming { mark_extraction(pending_import, :pending) }

        expect(Tracks::BoundaryDetector.new(user).reabsorb_orphan_points).to eq(0)

        expect(track_ids(orphans)).to all(be_nil)
      end

      it 'does not take orphans another track claimed in between' do
        other_track = create(:track, user: user, tracker_id: 'phone', start_at: 3.hours.ago, end_at: 3.hours.ago)
        between_choosing_and_claiming { Point.where(id: orphans.map(&:id)).update_all(track_id: other_track.id) }

        expect(Tracks::BoundaryDetector.new(user).reabsorb_orphan_points).to eq(0)

        expect(track_ids(orphans)).to all(eq(other_track.id))
      end
    end
  end
end

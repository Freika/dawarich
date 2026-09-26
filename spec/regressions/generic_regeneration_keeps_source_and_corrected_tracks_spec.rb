# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Generic track regeneration never deletes source or corrected tracks' do
  let(:user) { create(:user) }
  let(:base) { 3.days.ago.beginning_of_hour.to_i }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }

  def create_points(tracker_id:, offset:, import_id: nil)
    Array.new(6) do |i|
      create(:point, user: user, import_id: import_id, tracker_id: tracker_id, timestamp: base + offset + (i * 60),
                     lonlat: "POINT(#{13.4 + (offset / 1000.0) + (i * 0.0005)} 52.5)")
    end
  end

  def track_for(points, **attrs)
    track = create(:track, user: user, tracker_id: points.first.tracker_id,
                           start_at: Time.zone.at(points.first.timestamp),
                           end_at: Time.zone.at(points.last.timestamp), **attrs)
    Point.where(id: points.map(&:id)).update_all(track_id: track.id)
    track
  end

  def segment_on(track, **attrs)
    create(:track_segment, track: track, start_index: 0, end_index: 5, transportation_mode: :cycling, **attrs)
  end

  def run_daily_after(&)
    user.update!(points_count: user.points.count)
    Tracks::DailyGenerationJob.perform_now
    yield
    perform_enqueued_jobs(only: Tracks::ParallelGeneratorJob)
    perform_enqueued_jobs(only: Tracks::TimeChunkProcessorJob)
  end

  it 'keeps a source track the extraction wrote once the extraction has finished' do
    points = create_points(tracker_id: 'takeout', offset: 0, import_id: import.id)
    source_track = nil

    run_daily_after do
      source_track = track_for(points, import_id: import.id)
      import.update_columns(additional_data_extraction_status: Import.additional_data_extraction_statuses[:completed])
    end

    expect(Track.exists?(source_track.id)).to be(true)
    expect(Point.where(id: points.map(&:id)).pluck(:track_id)).to all(eq(source_track.id))
  end

  it 'keeps a generated track carrying a manual correction and still rebuilds a plain one' do
    corrected_points = create_points(tracker_id: 'phone', offset: 0)
    plain_points = create_points(tracker_id: 'watch', offset: 30)
    corrected_track = plain_track = nil

    run_daily_after do
      corrected_track = track_for(corrected_points)
      segment_on(corrected_track, source: 'user', corrected_at: 1.day.ago)
      plain_track = track_for(plain_points)
      segment_on(plain_track, source: 'inferred')
    end

    expect(Track.exists?(corrected_track.id)).to be(true)
    expect(Track.exists?(plain_track.id)).to be(false)
    expect(Point.where(id: plain_points.map(&:id)).pluck(:track_id)).to all(be_present)
  end

  it 'keeps a generated track carrying source segments' do
    points = create_points(tracker_id: 'phone', offset: 0, import_id: import.id)
    adopted_track = nil

    run_daily_after do
      adopted_track = track_for(points)
      segment_on(adopted_track, source: 'google_phone_takeout')
    end

    expect(Track.exists?(adopted_track.id)).to be(true)
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Track generation reads the device of stamped points from point_sources' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :owntracks, name: 'phone.rec') }
  let(:base) { 3.days.ago.beginning_of_hour.to_i }
  let(:phone) { PointSource.create!(digest: SecureRandom.hex(16), tracker_id: 'phone') }

  def stamped_points(offsets, import_id: nil, start: base)
    points = offsets.map do |offset|
      create(:point, user: user, import_id: import_id, tracker_id: 'phone', timestamp: start + offset,
                     lonlat: "POINT(#{13.4 + (offset * 0.00001)} 52.5)")
    end
    Point.where(id: points.map(&:id)).update_all(source_id: phone.id, tracker_id: 'legacy-phone')
    points
  end

  def track_over(points, **attrs)
    track = create(:track, user: user, tracker_id: 'phone', start_at: Time.zone.at(points.first.timestamp),
                           end_at: Time.zone.at(points.last.timestamp), **attrs)
    Point.where(id: points.map(&:id)).update_all(track_id: track.id)
    track
  end

  def corrected_track(offsets)
    track_over(stamped_points(offsets), created_at: 3.hours.ago).tap do |track|
      create(:track_segment, :anchored, track: track, start_at: track.start_at, end_at: track.end_at,
                                        transportation_mode: :cycling, source: 'user', corrected_at: 1.day.ago)
    end
  end

  def overlapping(kept)
    user.tracks.where.not(id: kept.id).where('start_at < ? AND end_at > ?', kept.end_at, kept.start_at)
  end

  it 'splits leftover orphans around a kept track of the same device' do
    stamped_points([0, 60, 120, 180], import_id: import.id)
    kept = corrected_track([240, 300, 360])
    stamped_points([420, 480, 540, 600], import_id: import.id)

    import.schedule_untracked_track_generation
    perform_enqueued_jobs(only: Tracks::ParallelGeneratorJob)
    perform_enqueued_jobs(only: Tracks::TimeChunkProcessorJob)

    expect(overlapping(kept)).to be_empty
  end

  it 'does not merge boundary tracks across a kept track of the same device' do
    earlier = track_over(stamped_points([0, 60, 120, 180]))
    later = track_over(stamped_points([480, 540, 600, 660]))
    corrected_track([240, 300, 360, 420])

    Tracks::BoundaryDetector.new(user).resolve_cross_chunk_tracks

    expect(user.tracks.where(id: [earlier.id, later.id]).count).to eq(2)
  end

  it 'reabsorbs orphans of the same device into a recent track' do
    recent_start = 2.hours.ago.to_i
    recent = track_over(stamped_points([0, 60, 120, 180, 240], start: recent_start))
    orphans = stamped_points([90, 150], start: recent_start)
    Point.where(id: orphans.map(&:id)).update_all(created_at: 10.minutes.ago)

    Tracks::BoundaryDetector.new(user).reabsorb_orphan_points

    expect(Point.where(id: orphans.map(&:id)).pluck(:track_id)).to all(eq(recent.id))
  end
end

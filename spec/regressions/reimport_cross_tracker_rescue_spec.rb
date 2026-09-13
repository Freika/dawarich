# frozen_string_literal: true

require 'rails_helper'

# End-to-end regression for `Tracks::TrackBuilder#reuse_existing_track` through
# its production caller `EnhancedImport::Writers::TrackWriter`.
#
# A re-import of the same source file yields a fresh `Import` row, so the
# EnhancedImport adapters derive a fresh `tracker_id`
# (`"import-#{import.id}-activity-#{started_at.to_i}"`) while the point
# timestamps — and therefore the track's `start_at`/`end_at` — stay
# byte-identical to the first import. The tracker-scoped unique index
# `index_tracks_on_user_tracker_start_end_unique` admits both rows, so two
# tracks for the same window but different `tracker_id`s coexist (Example 1
# proves this against the real writer).
#
# When a racing duplicate of the re-import collides on
# `(user_id, tracker_id, start_at, end_at)`, `create_track_from_points` rescues
# `RecordNotUnique` via `reuse_existing_track`. Before the fix that lookup was
# scoped only on `(user_id, start_at, end_at)`, so PostgreSQL could resolve it
# to the *first* import's different-tracker track in heap/ctid order and attach
# the loser's points to it, silently corrupting that track (Example 2).
RSpec.describe 're-import cross-tracker rescue attaches points to the same-tracker track',
               :non_transactional do
  let(:user) { create(:user) }
  let(:import_a) { create(:import, user: user, source: :google_phone_takeout) }
  let(:import_b) { create(:import, user: user, source: :google_phone_takeout) }
  let(:writer_a) { EnhancedImport::Writers::TrackWriter.new(user, import_a) }
  let(:writer_b) { EnhancedImport::Writers::TrackWriter.new(user, import_b) }

  let(:base_ts) { Time.zone.parse('2026-03-01 10:00:00').to_i }
  let(:window_start) { Time.zone.at(base_ts) }
  let(:window_end) { Time.zone.at(base_ts + 120) }
  let(:base) { base_ts }

  # Mirror the adapter's tracker_id scheme exactly so the assertion reflects
  # the real key the production writer would compute.
  def tracker_id_for(import)
    "import-#{import.id}-activity-#{base_ts}"
  end

  def extracted_for(import)
    EnhancedImport::Extracted::Track.new(
      tracker_id: tracker_id_for(import),
      start_at: window_start,
      end_at: window_end,
      distance_m: 900,
      transportation_mode: 'driving',
      confidence: 90,
      source_label: 'google_phone_takeout',
      segments: [
        EnhancedImport::Extracted::TrackSegment.new(
          start_index: 0, end_index: 0, transportation_mode: 'driving',
          confidence: 90, source_label: 'google_phone_takeout'
        )
      ]
    )
  end

  # Byte-identical timestamps across both imports (re-import of the same
  # source file); only the coordinates differ so the (user, lonlat, timestamp)
  # uniqueness validation on Point is not tripped.
  def make_points(import, device, lat)
    Array.new(3) do |i|
      create(
        :point,
        user: user,
        import_id: import.id,
        tracker_id: device,
        timestamp: base_ts + (i * 60),
        latitude: lat + (i * 0.001),
        longitude: 13.405 + (i * 0.001),
        track_id: nil
      )
    end
  end

  before do
    make_points(import_a, 'device-A', 52.5)
    make_points(import_b, 'device-A', 40.0)
  end

  it 'a re-import creates a co-existing different-tracker track in the same window' do
    track_a, created_a = writer_a.upsert(
      extracted_for(import_a), skip_segment_detection: true
    )
    expect(created_a).to be(true)
    expect(track_a).to be_a(Track)

    track_b, created_b = writer_b.upsert(
      extracted_for(import_b), skip_segment_detection: true
    )
    expect(created_b).to be(true)
    expect(track_b).to be_a(Track)

    same_window = Track.where(user_id: user.id, start_at: window_start, end_at: window_end)
    expect(same_window.count).to eq(2)
    expect(same_window.pluck(:tracker_id)).to contain_exactly(
      "import-#{import_a.id}-activity-#{base}",
      "import-#{import_b.id}-activity-#{base}"
    )
  end

  it 'a racing duplicate of the re-import attaches its points to the same-tracker track' do
    track_a, = writer_a.upsert(
      extracted_for(import_a), skip_segment_detection: true
    )
    track_b, = writer_b.upsert(
      extracted_for(import_b), skip_segment_detection: true
    )

    expect(track_a.id).not_to eq(track_b.id)
    expect(track_b.tracker_id).to eq(tracker_id_for(import_b))

    # The losing side of a racing re-import has already loaded a fresh set of
    # unattached points for the same window (exactly what `matching_points`
    # returns before either upsert commits). Its timestamps match track_b's
    # window so the new insert collides on the unique index.
    dup_points = make_points(import_b, 'device-A', 53.0)
    expect(Point.where(id: dup_points.map(&:id)).pluck(:track_id).uniq).to eq([nil])

    loser_track = writer_b.create_track_from_points(
      dup_points, 1000,
      tracker_id: track_b.tracker_id,
      skip_segment_detection: true
    )

    # The rescue must return the same-tracker winner, never the first import's
    # different-tracker track.
    expect(loser_track.id).to eq(track_b.id)
    expect(loser_track.tracker_id).to eq(track_b.tracker_id)

    # The duplicate's points land on track_b only.
    expect(Point.where(id: dup_points.map(&:id)).pluck(:track_id).uniq).to eq([track_b.id])
    expect(Point.where(id: dup_points.map(&:id), track_id: track_a.id).count).to eq(0)

    # The first import's track is left untouched — no cross-tracker corruption.
    expect(Point.where(id: dup_points.map(&:id)).count).to eq(dup_points.size)
    expect(track_a.reload.points.count).to eq(3)
  end
end

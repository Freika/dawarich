# frozen_string_literal: true

# Tracks are built per tracker, so a gap in one tracker's track never sees the
# points another tracker recorded during it. When a whole track of another
# tracker fits inside such a gap (a watch GPX imported over the stretch where
# low accuracy phone points were deleted), the gap is a handoff: the outer
# track is cut there instead of bridging it with a straight line. Trackers that
# recorded alongside each other keep their tracks whole.
class Tracks::HandoffSplitter
  include Tracks::TrackBuilder

  # ponytail: same recency window as BoundaryDetector; a resolver that runs more
  # than an hour after its chunks misses the split until the next recalculation.
  RECENT_WINDOW = 1.hour

  def self.handoff_between?(user, tracker_id, gap_start, gap_end)
    other_tracker_tracks(user, tracker_id)
      .where('start_at > :from AND start_at < :to AND end_at < :to', from: gap_start, to: gap_end)
      .exists?
  end

  def self.other_tracker_tracks(user, tracker_id)
    user.tracks.where('tracker_id IS DISTINCT FROM ?', tracker_id)
  end

  def initialize(user)
    @user = user
  end

  def call
    outer_tracks.to_a.sum { |track| split(track) }
  end

  private

  attr_reader :user

  def outer_tracks
    user.tracks
        .joins('JOIN tracks inner_tracks ON inner_tracks.user_id = tracks.user_id ' \
               'AND inner_tracks.tracker_id IS DISTINCT FROM tracks.tracker_id ' \
               'AND inner_tracks.start_at > tracks.start_at AND inner_tracks.start_at < tracks.end_at ' \
               'AND inner_tracks.end_at < tracks.end_at')
        .where('tracks.created_at > :since OR inner_tracks.created_at > :since', since: RECENT_WINDOW.ago)
        .distinct
  end

  def split(track)
    points = track.points.order(:timestamp, :id).to_a
    cuts = cut_indexes(track, points.map(&:timestamp))
    return 0 if cuts.empty?

    ActiveRecord::Base.transaction do
      track.destroy!
      ([0] + cuts).zip(cuts + [points.size]).each do |from, to|
        section = points[from...to]
        create_track_from_points(section, Point.calculate_distance_for_array_geocoder(section, :m))
      end
    end
    1
  end

  def cut_indexes(track, timestamps)
    self.class.other_tracker_tracks(user, track.tracker_id)
        .where('start_at > :from AND start_at < :to AND end_at < :to', from: track.start_at, to: track.end_at)
        .pluck(:start_at, :end_at)
        .filter_map do |inner_start, inner_end|
          index = timestamps.bsearch_index { |timestamp| timestamp >= inner_start.to_i }
          index if index&.positive? && timestamps[index] > inner_end.to_i
        end
        .uniq.sort
  end
end

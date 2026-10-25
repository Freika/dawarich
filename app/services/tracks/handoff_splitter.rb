# frozen_string_literal: true

# Tracks are built per tracker, so a gap in one tracker's track never sees the
# points another tracker recorded during it. When a whole track of another
# tracker fits inside such a gap (a watch GPX imported over the stretch where
# low accuracy phone points were deleted), the gap is a handoff: the outer
# track is cut there instead of bridging it with a straight line. Trackers that
# recorded alongside each other keep their tracks whole.
class Tracks::HandoffSplitter
  include Tracks::TrackBuilder

  RECENT_WINDOW = 1.hour

  CONTAINS_OTHER_TRACKER = 'JOIN tracks inner_tracks ON inner_tracks.user_id = tracks.user_id ' \
                           "AND COALESCE(inner_tracks.tracker_id, '') <> COALESCE(tracks.tracker_id, '') " \
                           'AND inner_tracks.start_at > tracks.start_at ' \
                           'AND inner_tracks.start_at < tracks.end_at ' \
                           'AND inner_tracks.end_at < tracks.end_at'

  def self.handoff_between?(user, tracker_id, gap_start, gap_end)
    other_tracker_tracks(user, tracker_id)
      .where('start_at > :from AND start_at < :to AND end_at < :to', from: gap_start, to: gap_end)
      .exists?
  end

  def self.other_tracker_tracks(user, tracker_id)
    user.tracks.where("COALESCE(tracker_id, '') <> COALESCE(?, '')", tracker_id)
  end

  def initialize(user)
    @user = user
  end

  def call(since: RECENT_WINDOW.ago)
    outer_track_ids(since).sum do |track_id|
      track = user.tracks.find_by(id: track_id)
      track ? split(track) : 0
    rescue StandardError => e
      ExceptionReporter.call(e, "Failed to split track #{track_id} at a handoff for user #{user.id}")
      0
    end
  end

  private

  attr_reader :user

  def outer_track_ids(since)
    return [] unless user.tracks.where('created_at > ?', since).exists?

    containing = user.tracks.joins(CONTAINS_OTHER_TRACKER).distinct
    (containing.where('tracks.created_at > ?', since).pluck(:id) + outers_of_recent(containing, since)).uniq
  end

  def outers_of_recent(containing, since)
    older = user.tracks.where('created_at <= ?', since)
    longest = older.pick(Arel.sql('MAX(EXTRACT(EPOCH FROM end_at - start_at))'))
    return [] if longest.nil?

    containing.where('tracks.created_at <= :since AND inner_tracks.created_at > :since', since:)
              .where('tracks.start_at > inner_tracks.start_at - make_interval(secs => ?)', longest.to_f)
              .pluck(:id)
  end

  def split(track)
    ids_and_times = track.points.order(:timestamp, :id).pluck(:id, :timestamp)
    cuts = cut_indexes(track, ids_and_times.map(&:last))
    return 0 if cuts.empty?

    points_by_id = Point.where(id: ids_and_times.map(&:first)).index_by(&:id)
    points = ids_and_times.map { |id, _| points_by_id[id] }
    sections = ([0] + cuts).zip(cuts + [points.size]).map { |from, to| points[from...to] }

    split_into_sections(track, sections) ? 1 : 0
  end

  def split_into_sections(track, sections)
    kept = sections.find { |section| section.size > 1 }
    split = false

    ActiveRecord::Base.transaction(requires_new: true) do
      if kept
        Point.where(id: (sections - [kept]).flatten.map(&:id)).update_all(track_id: nil)
        keep_section(track, kept)
      else
        track.destroy!
      end

      (sections - [kept]).each do |section|
        next if section.size < 2

        distance = Point.calculate_distance_for_array_geocoder(section, :m)
        raise ActiveRecord::Rollback unless create_track_from_points(section, distance)
      end
      split = true
    end

    Rails.logger.warn("event=tracks.handoff_split_rolled_back user_id=#{user.id} track_id=#{track.id}") unless split

    log_split(track, sections) if split
    split
  end

  def keep_section(track, section)
    elevation = calculate_elevation_stats(section)
    track.track_segments.auto_classified.delete_all
    track.update!(start_at: Time.zone.at(section.first.timestamp), end_at: Time.zone.at(section.last.timestamp),
                  elevation_gain: elevation[:gain], elevation_loss: elevation[:loss],
                  elevation_max: elevation[:max], elevation_min: elevation[:min])
    detect_and_create_segments(track, section)
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

  def log_split(track, sections)
    Rails.logger.info(
      "event=tracks.handoff_split user_id=#{user.id} track_id=#{track.id} sections=#{sections.size}"
    )
  end
end

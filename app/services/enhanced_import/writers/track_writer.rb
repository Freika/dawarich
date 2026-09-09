# frozen_string_literal: true

module EnhancedImport
  module Writers
    class TrackWriter
      include Tracks::TrackBuilder

      attr_reader :user

      def initialize(user, import)
        @user = user
        @import = import
      end

      def upsert(extracted, skip_segment_detection: false)
        existing = find_existing(extracted)

        return [rebuild_segments(existing, skip_segment_detection), false] if existing

        points = matching_points(extracted)

        # Backfilling an old import finds every point already owned by a
        # generated track. Stealing them would empty that track, so annotate it
        # with the source's classification instead of building a duplicate.
        if points.size < 2
          adopted = adopt_generated_track(extracted)
          return [adopted, false] if adopted

          return [nil, false]
        end

        track = create_track_from_points(
          points,
          extracted.distance_m || 0,
          tracker_id: extracted.tracker_id,
          skip_segment_detection: skip_segment_detection
        )
        track&.update_column(:import_id, @import.id)
        [track, true]
      rescue ActiveRecord::RecordNotUnique
        existing = find_existing(extracted)
        [existing, false]
      end

      private

      # The stored start_at is the first matching point's timestamp, not the
      # activity boundary, so tracker_id is the only stable key here.
      def find_existing(extracted)
        Track.where(user_id: user.id, tracker_id: extracted.tracker_id).first
      end

      # The track that already owns this import's points for the same window.
      def adopt_generated_track(extracted)
        track_ids = Point.where(
          user_id: user.id,
          import_id: @import.id,
          timestamp: extracted.start_at.to_i..extracted.end_at.to_i
        ).where.not(track_id: nil).distinct.pluck(:track_id)

        return nil unless track_ids.size == 1

        track = Track.find_by(id: track_ids.first, user_id: user.id)
        return nil if track.nil?

        # This track belongs to Dawarich's own generation, not to the
        # extraction, so its segmentation is never overwritten and undo can
        # never reach it. Only classify it when it carries none of its own.
        return nil if track.track_segments.exists?

        track
      end

      # A re-extraction may flip "trust the source app's classification", so the
      # existing segments are rebuilt to match whichever side the user picked.
      def rebuild_segments(track, skip_segment_detection)
        track.track_segments.destroy_all

        unless skip_segment_detection
          points = track.points.order(:timestamp).to_a
          detect_and_create_segments(track, points) if points.size >= 2
        end

        track.update_dominant_mode!
        track
      end

      # Track generation runs against the same import; claiming a point that
      # already belongs to a generated track would empty that track out.
      def matching_points(extracted)
        points = Point.where(
          user_id: user.id,
          import_id: @import.id,
          track_id: nil,
          timestamp: extracted.start_at.to_i..extracted.end_at.to_i
        ).order(:timestamp).to_a

        dominant_device_points(points)
      end

      # A track must never span two devices: Google's Records.json carries every
      # device on one account, so a window can hold points the user recorded on a
      # phone and a tablet at once. Stitching them produces invented travel
      # between the two. Keep the device with the most points in the window and
      # leave the rest for their own activity.
      def dominant_device_points(points)
        grouped = points.group_by(&:tracker_id)
        return points if grouped.size <= 1

        grouped.values.min_by { |group| [-group.size, group.first.timestamp] }
      end
    end
  end
end

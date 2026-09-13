# frozen_string_literal: true

class Tracks::GeojsonSerializer
  DEFAULT_COLOR = '#6366F1'

  # Emoji mapping for transportation modes (for debug visualization)
  MODE_EMOJIS = {
    'walking' => '🚶',
    'running' => '🏃',
    'cycling' => '🚴',
    'driving' => '🚗',
    'bus' => '🚌',
    'train' => '🚆',
    'flying' => '✈️',
    'boat' => '⛵',
    'motorcycle' => '🏍️',
    'stationary' => '📍',
    'unknown' => '❓'
  }.freeze

  # Color mapping for segment visualization (Tailwind 500)
  MODE_COLORS = {
    'walking' => '#22C55E',    # Green
    'running' => '#F97316',    # Orange
    'cycling' => '#3B82F6',    # Blue
    'driving' => '#EF4444',    # Red
    'bus' => '#EAB308',        # Yellow
    'train' => '#84CC16',      # Lime
    'flying' => '#06B6D4',     # Cyan
    'boat' => '#14B8A6',       # Teal
    'motorcycle' => '#EC4899', # Pink
    'stationary' => '#94A3B8', # Slate
    'unknown' => '#CBD5E1'     # Light slate
  }.freeze

  def initialize(tracks, include_segments: false)
    @tracks = Array.wrap(tracks)
    @include_segments = include_segments
  end

  def call
    {
      type: 'FeatureCollection',
      features: tracks.map { |track| feature_for(track) }
    }
  end

  private

  attr_reader :tracks, :include_segments

  def feature_for(track)
    {
      type: 'Feature',
      geometry: geometry_for(track),
      properties: properties_for(track)
    }
  end

  def properties_for(track)
    base_properties(track).merge(segment_properties(track))
  end

  def base_properties(track)
    {
      id: track.id,
      color: DEFAULT_COLOR,
      start_at: track.start_at.iso8601,
      end_at: track.end_at.iso8601,
      distance: track.distance.to_i,
      avg_speed: track.avg_speed.to_f,
      duration: track.duration
    }
  end

  def segment_properties(track)
    props = {
      dominant_mode: track.dominant_mode,
      dominant_mode_emoji: emoji_for_mode(track.dominant_mode)
    }

    # Lightweight mode timeline for per-segment emoji in timeline scrubber
    props[:mode_timeline] = mode_timeline_for(track)

    # Only include full segments when explicitly requested (lazy-loading optimization)
    props[:segments] = segments_for(track) if include_segments

    props
  end

  def segments_for(track)
    return [] unless track.respond_to?(:track_segments)

    segments = sorted_segments(track)
    return [] if segments.empty?

    # Cumulative fallback time for legacy index-anchored segments
    current_time = track.start_at
    segments.map do |segment|
      serialized = serialize_segment(segment, current_time)
      current_time += (segment.duration || 0).seconds
      serialized
    end
  end

  # Segments of one track are era-homogeneous: either all time-anchored (new
  # pipeline) or all index-anchored (legacy, pre-backfill).
  def sorted_segments(track)
    track.track_segments.to_a.sort_by do |segment|
      segment.start_at ? segment.start_at.to_f : (segment.start_index || 0).to_f
    end
  end

  def serialize_segment(segment, start_time = nil)
    segment_identity(segment)
      .merge(segment_stats(segment))
      .merge(segment_times(segment, start_time))
  end

  def segment_identity(segment)
    {
      id: segment.id,
      mode: segment.transportation_mode,
      emoji: emoji_for_mode(segment.transportation_mode),
      color: color_for_mode(segment.transportation_mode),
      start_index: segment.start_index,
      end_index: segment.end_index,
      coordinates: segment_coordinates(segment)
    }
  end

  def segment_coordinates(segment)
    return nil unless segment.respond_to?(:path) && segment.path

    segment.path.points.map { |point| [point.x, point.y] }
  end

  def segment_stats(segment)
    {
      distance: segment.distance,
      duration: segment.duration,
      avg_speed: segment.avg_speed&.to_f,
      confidence: segment.confidence
    }
  end

  def segment_times(segment, start_time)
    return { start_time: segment.start_at.to_i, end_time: segment.end_at.to_i } if segment.start_at && segment.end_at
    return {} unless start_time

    end_time = start_time + (segment.duration || 0).seconds
    {
      start_time: start_time.to_i,
      end_time: end_time.to_i
    }
  end

  def mode_timeline_for(track)
    return [] unless track.respond_to?(:track_segments)

    segments = sorted_segments(track)
    return [] if segments.empty?

    return anchored_mode_timeline(segments) if segments.all?(&:start_at)

    legacy_mode_timeline(track, segments)
  end

  def anchored_mode_timeline(segments)
    segments.map do |segment|
      {
        start_time: segment.start_at.to_i,
        end_time: segment.end_at.to_i,
        emoji: emoji_for_mode(segment.transportation_mode)
      }
    end
  end

  # Index-proportional approximation for legacy segments not yet backfilled.
  def legacy_mode_timeline(track, segments)
    track_start = track.start_at.to_f
    track_end = track.end_at.to_f
    total_points = (segments.last.end_index || 0) + 1
    time_span = track_end - track_start

    segments.map do |segment|
      seg_start = track_start + ((segment.start_index.to_f / total_points) * time_span)
      seg_end = track_start + (((segment.end_index + 1).to_f / total_points) * time_span)
      {
        start_time: seg_start.to_i,
        end_time: seg_end.to_i,
        emoji: emoji_for_mode(segment.transportation_mode)
      }
    end
  end

  def emoji_for_mode(mode)
    MODE_EMOJIS[mode] || MODE_EMOJIS['unknown']
  end

  def color_for_mode(mode)
    MODE_COLORS[mode] || MODE_COLORS['unknown']
  end

  def geometry_for(track)
    geometry = RGeo::GeoJSON.encode(track.original_path)
    geometry.respond_to?(:as_json) ? geometry.as_json.deep_symbolize_keys : geometry
  end
end

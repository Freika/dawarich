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

    # Only include segments when explicitly requested (lazy-loading optimization)
    props[:segments] = segments_for(track) if include_segments

    props
  end

  def segments_for(track)
    return [] unless track.respond_to?(:track_segments)

    segments = track.track_segments.to_a.sort_by(&:start_index)
    return [] if segments.empty?

    # Calculate cumulative start times from track start
    current_time = track.start_at
    segments.map do |segment|
      serialized = serialize_segment(segment, current_time)
      # Move current_time forward by this segment's duration
      current_time += (segment.duration || 0).seconds
      serialized
    end
  end

  def serialize_segment(segment, start_time = nil)
    segment_identity(segment)
      .merge(segment_stats(segment))
      .merge(segment_times(segment, start_time))
  end

  def segment_identity(segment)
    {
      mode: segment.transportation_mode,
      emoji: emoji_for_mode(segment.transportation_mode),
      color: color_for_mode(segment.transportation_mode),
      start_index: segment.start_index,
      end_index: segment.end_index
    }
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
    return {} unless start_time

    end_time = start_time + (segment.duration || 0).seconds
    {
      start_time: start_time.to_i,
      end_time: end_time.to_i
    }
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

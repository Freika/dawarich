# frozen_string_literal: true

class Tracks::GeojsonSerializer
  DEFAULT_COLOR = '#ff0000'

  def initialize(tracks)
    @tracks = Array.wrap(tracks)
  end

  def call
    {
      type: 'FeatureCollection',
      features: tracks.map { |track| feature_for(track) }
    }
  end

  private

  attr_reader :tracks

  def feature_for(track)
    {
      type: 'Feature',
      geometry: geometry_for(track),
      properties: properties_for(track)
    }
  end

  def properties_for(track)
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

  def geometry_for(track)
    geometry = RGeo::GeoJSON.encode(track.original_path)
    geometry.respond_to?(:as_json) ? geometry.as_json.deep_symbolize_keys : geometry
  end
end

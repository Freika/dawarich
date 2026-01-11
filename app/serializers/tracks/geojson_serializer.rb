# frozen_string_literal: true

module Tracks
  class GeojsonSerializer
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
        geometry: RGeo::GeoJSON.encode(track.original_path),
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
  end
end
